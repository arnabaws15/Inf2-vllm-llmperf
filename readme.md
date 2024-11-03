# Use this bash script to bootstrap your inf2 instance #

## Pre-requisites ##
- Before running this script you must have a HuggingFace token if you are using a model that requires you to agree to T&C.
- Go to huggingface.co and login/register for an account
- Go to your profile --> Settings --> Access Tokens to create your personal access token
- Next go to the model page for the provider and click to subscribe and agree to the T&C.
- Now you're ready to execute the script
- Launch any Inferentia2 EC2 instance (xl, 8xl, 24xl, or 48xl)
- Right now support for *paged-attention* is not available. So the script updates a configuration file to increase the block-size. See line 59 if you want to not allow a certain size.
- Larger the instance you can play with the tensor-parallel value in the script on line 75. See below:
  
`python3 -m vllm.entrypoints.openai.api_server --model meta-llama/Meta-Llama-3.1-8B-Instruct --max-num-seqs 8 --max-model-len 4096 --block-size 4096 --device neuron --tensor-parallel-size 2 > vllm_server.log 2>&1 &`


## Launch Script in HOME DIR for best experience ##

`. ./inf2-vllm-with-llmperf.sh`

