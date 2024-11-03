#!/bin/bash
# Run this script in Ubuntu on inf2.8xlarge or similar inf2 instance
source /opt/aws_neuronx_venv_transformers_neuronx/bin/activate

# Clone llmperf repo
git clone https://github.com/ray-project/llmperf.git
cd llmperf
pip install -e .

# Create a script to trigger llmperf
cat << 'EOF' > benchmark.sh
#!/bin/bash
model=${1:-meta-llama/Meta-Llama-3.1-8B-Instruct}
echo $model
echo "\n"
vu=${2:-1}
echo $vu
export OPENAI_API_KEY=EMPTY
# inf2
export OPENAI_API_BASE="http://localhost:8000/v1"  
max_requests=$(expr ${vu} \* 8 )
date_str=$(date '+%Y-%m-%d-%H-%M-%S')
python3 ./token_benchmark_ray.py \
 --model ${model} \
 --mean-input-tokens 3000 \
 --stddev-input-tokens 200 \
 --mean-output-tokens 512 \
 --stddev-output-tokens 200 \
 --max-num-completed-requests ${max_requests} \
 --timeout 7200 \
 --num-concurrent-requests ${vu} \
 --results-dir "vllm_bench_results/${date_str}" \
 --llm-api openai \
 --additional-sampling-params '{}'
EOF
echo "Done with benchmark.sh"
chmod +x benchmark.sh

# go back to home directory
cd $HOME 

# Clone vllm repo 
git clone https://github.com/vllm-project/vllm.git
cd vllm
git checkout v0.6.2

# Change vllm/engine/arg_util.py to add more blocks choices=[8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072]

## Specify the file path
file_path="vllm/engine/arg_utils.py"

## Check if the file exists
if [ ! -f "$file_path" ]; then
    echo "Error: File not found at $file_path"
    # exit 1
fi

## Perform the replacement
sed -i 's/choices=\[8, 16, 32\]/choices=[8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536, 131072]/' "$file_path"

## Check if the replacement was successful
if [ $? -eq 0 ]; then
    echo "Replacement successful in $file_path"
else
    echo "Error: Replacement failed in $file_path"
    #exit 1
fi

# Now install vllm in main folder
pip install .
pip install --upgrade triton
cd $HOME

# Now start vllm server
python3 -m vllm.entrypoints.openai.api_server --model meta-llama/Meta-Llama-3.1-8B-Instruct --max-num-seqs 8 --max-model-len 4096 --block-size 4096 --device neuron --tensor-parallel-size 2 > vllm_server.log 2>&1 &

## Capture the vllm PID
PID=$!
echo "vLLM server started with PID $PID. Output is being logged to vllm_server.log"

# Function to check for the Uvicorn running message
check_uvicorn_running() {
    if grep -q "Uvicorn running on http://0.0.0.0:8000" vllm_server.log; then
        return 0  # Success
    else
        return 1  # Not found
    fi
}

# Maximum number of attempts (60 attempts * 1 minute = 1 hour max wait time)
max_attempts=60
attempt=1

# Loop until the message is found or max attempts are reached
while ! check_uvicorn_running; do
    if [ $attempt -ge $max_attempts ]; then
        echo "Error: Uvicorn not running after $max_attempts attempts. Exiting."
        exit 1
    fi
    
    echo "Attempt $attempt: Uvicorn not yet running. Waiting for 1 minute..."
    sleep 60
    ((attempt++))
done
echo "Uvicorn is now running on http://0.0.0.0:8000. Proceeding with the next command."

# Function to make the curl request and check the status code
check_status() {
    # Make the curl request and capture both the HTTP status code and the response body
    response=$(curl -s -w "\n%{http_code}" -X POST -H "Content-Type: application/json" \
        http://localhost:8000/v1/chat/completions \
        -d '{"model": "meta-llama/Meta-Llama-3.1-8B-Instruct", "messages": [{"role": "user", "content": "The capital of France is"}, {"role": "assistant", "content": "You are a helpful assistant."}]}')

    # Extract the status code (last line of the response)
    status_code=$(echo "$response" | tail -n1)

    # Extract the response body (everything except the last line)
    body=$(echo "$response" | sed '$d')

    # Check if the status code is 200
    if [ "$status_code" -eq 200 ]; then
        echo "Received 200 OK response. Proceeding with execution of the llmperf script - benchmark.sh."
        echo "Response body:"
        echo "$body" | jq
        return 0
    else
        echo "Error: Received status code $status_code. Exiting."
        echo "Response body:"
        echo "$body" | jq
        return 1
    fi
}

# Script execution
if check_status; then
    # Run llmperf benchmark.sh
    echo "Proceeding with script"
    cd $HOME/llmperf
    . ./benchmark.sh "" 2
else
    echo "Error was encountered in script"
fi
