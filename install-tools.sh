
    #!/bin/bash
    agentuser=${AGENT_USER}
    pool=${AGENT_POOL}
    pat=${AGENT_TOKEN}
    azdourl=${AZDO_URL}
    
    # install az cli
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    
    # install docker
    sudo apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
    sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic stable"
    sudo apt update
    sudo apt install -y docker-ce
    sudo usermod -aG docker $agentuser
    
    # install kubectl
    curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add
    sudo apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
    sudo apt update
    sudo apt-get install -y kubectl
    
    # install kubelogin using Homebrew
    sudo /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    sudo brew install int128/kubelogin/kubelogin

    # install helm
    curl -o helm.tar.gz https://get.helm.sh/helm-v3.3.4-linux-amd64.tar.gz
    tar zxvf helm.tar.gz
    sudo mv linux-amd64/helm /usr/local/bin/helm
    rm -rf linux-amd64
    rm -f helm.tar.gz
    
    # download azdo agent
    mkdir -p /opt/azdo && cd /opt/azdo
    cd /opt/azdo
    sudo curl -o azdoagent.tar.gz https://vstsagentpackage.azureedge.net/agent/2.214.1/vsts-agent-linux-x64-2.214.1.tar.gz
    sudo tar xzvf azdoagent.tar.gz
    sudo rm -f azdoagent.tar.gz
    
    # configure as azdouser
    sudo chown -R $agentuser /opt/azdo
    sudo chmod -R 755 /opt/azdo
    sudo runuser -l $agentuser -c "/opt/azdo/config.sh --unattended --url $azdourl --auth pat --token $pat --pool $pool --acceptTeeEula"
    
    # install and start the service
    sudo ./svc.sh install
    sudo ./svc.sh start