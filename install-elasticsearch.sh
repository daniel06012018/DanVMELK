#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2015 Microsoft Azure
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

help()
{
    echo "This script installs Elasticsearch on Ubuntu"
    echo "Parameters:"
    echo "  -n elasticsearch cluster name"
    echo "  -m configure as master node (default: off)"
    echo "  -h view this help content"
}

# Log method to control/redirect log output
log()
{
    echo "$1"
}

log "Begin execution of Elasticsearch script extension on ${HOSTNAME}"

if [ "${UID}" -ne 0 ];
then
    log "Script executed without root permissions"
    echo "You must be root to run this program." >&2
    exit 3
fi

# TEMP FIX - Re-evaluate and remove when possible
# This is an interim fix for hostname resolution in current VM
grep -q "${HOSTNAME}" /etc/hosts
if [ $? == 0 ]
then
  echo "${HOSTNAME} found in /etc/hosts"
else
  echo "${HOSTNAME} not found in /etc/hosts"
  # Append it to the hosts file if not there
  echo "127.0.0.1 ${HOSTNAME}" >> /etc/hosts
  log "hostname ${HOSTNAME} added to /etc/hosts"
fi

#Script Parameters
CLUSTER_NAME="es-azure"
ES_VERSION="5.1.2"
IS_DATA_NODE=1

#Loop through options passed
while getopts :n:mh optname; do
  log "Option $optname set with value ${OPTARG}"
  case $optname in
    n) #set cluster name
      CLUSTER_NAME=${OPTARG}
      ;;
    m) #set master mode
      IS_DATA_NODE=0
      ;;
    h) #show help
      help
      exit 2
      ;;
    \?) #unrecognized option - show help
      echo -e \\n"Option -${BOLD}$OPTARG${NORM} not allowed."
      help
      exit 2
      ;;
  esac
done

# Install Oracle Java
install_java()
{
       add-apt-repository ppa:openjdk-r/ppa
    apt-get -q -y update  > /dev/null
    apt-get -q -y install openjdk-8-jdk > /dev/null
}

install_es()
{
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
    apt-get install apt-transport-https
    echo "deb https://artifacts.elastic.co/packages/5.x/apt stable main" | tee -a /etc/apt/sources.list.d/elastic-5.x.list    
    apt-get update -y 
    apt-get install -y elasticsearch
    pushd /usr/share/elasticsearch/
    bin/elasticsearch-plugin install x-pack --batch
    popd
    
    if [ ${IS_DATA_NODE} -eq 0 ]; 
    then
        install_kibana() {
    # default - ES 2.3.1
	kibana_url="https://artifacts.elastic.co/downloads/kibana/kibana-6.7.2-linux-x86_64.tar.gz"
	
	
	if [[ "${ES_VERSION}" == "2.2.2" ]]; 
    then
		kibana_url="https://download.elastic.co/kibana/kibana/kibana-4.4.2-linux-x64.tar.gz"
	fi
    
    if [[ "${ES_VERSION}" == "2.1.2" ]]; 
    then
        kibana_url="https://download.elastic.co/kibana/kibana/kibana-4.3.3-linux-x64.tar.gz"
    fi
    
    if [[ "${ES_VERSION}" == "1.7.5" ]]; 
    then
        kibana_url="https://download.elastic.co/kibana/kibana/kibana-4.1.6-linux-x64.tar.gz"
    fi
    
    groupadd -g 999 kibana
    useradd -u 999 -g 999 kibana

    mkdir -p /opt/kibana
    curl -s -o kibana.tar.gz ${kibana_url}
    tar xvf kibana.tar.gz -C /opt/kibana/ --strip-components=1 > /dev/null

    chown -R kibana: /opt/kibana
    mv /opt/kibana/config/kibana.yml /opt/kibana/config/kibana.yml.bak

    if [[ "${ES_VERSION}" == \2* ]];
    then
        echo "elasticsearch.url: \"$ELASTICSEARCH_URL\"" >> /opt/kibana/config/kibana.yml
    else
        cat /opt/kibana/config/kibana.yml.bak | sed "s|http://localhost:9200|${ELASTICSEARCH_URL}|" >> /opt/kibana/config/kibana.yml 
    fi

    # install the marvel plugin for 2.x
    if [ ${INSTALL_MARVEL} -ne 0 ];
    then
		if [[ "${ES_VERSION}" == \2* ]];
        then
            /opt/kibana/bin/kibana plugin --install elasticsearch/marvel/${ES_VERSION}
        fi

        # for 1.x marvel is installed only within the cluster, not on the kibana node 
    fi
    
    # install the sense plugin for 2.x
    if [ ${INSTALL_SENSE} -ne 0 ];
    then
        if [[ "${ES_VERSION}" == \2* ]];
        then
            /opt/kibana/bin/kibana plugin --install elastic/sense
        fi
                
        # for 1.x sense is not supported 
    fi

# Add upstart task and start kibana service
cat << EOF > /etc/init/kibana.conf
    # kibana
    description "Elasticsearch Kibana Service"

    start on starting
    script
        /opt/kibana/bin/kibana
    end script
EOF

    chmod +x /etc/init/kibana.conf
    service kibana start
    fi
}

configure_es()
{
	log "Update configuration"
	mv /etc/elasticsearch/elasticsearch.yml /etc/elasticsearch/elasticsearch.bak
	echo "cluster.name: $CLUSTER_NAME" >> /etc/elasticsearch/elasticsearch.yml
	echo "node.name: ${HOSTNAME}" >> /etc/elasticsearch/elasticsearch.yml
	echo "discovery.zen.minimum_master_nodes: 2" >> /etc/elasticsearch/elasticsearch.yml
	echo 'discovery.zen.ping.unicast.hosts: ["10.0.0.10", "10.0.0.11", "10.0.0.12"]' >> /etc/elasticsearch/elasticsearch.yml
	echo "network.host: _site_" >> /etc/elasticsearch/elasticsearch.yml
	echo "bootstrap.memory_lock: true" >> /etc/elasticsearch/elasticsearch.yml
        echo "xpack.security.enabled: false" >> /etc/elasticsearch/elasticsearch.yml

	if [ ${IS_DATA_NODE} -eq 1 ]; then
	    echo "node.master: false" >> /etc/elasticsearch/elasticsearch.yml
	    echo "node.data: true" >> /etc/elasticsearch/elasticsearch.yml
	else
        echo "node.master: true" >> /etc/elasticsearch/elasticsearch.yml
        echo "node.data: false" >> /etc/elasticsearch/elasticsearch.yml
	fi
}

configure_system()
{
	echo "options timeout:1 attempts:5" >> /etc/resolvconf/resolv.conf.d/head
	resolvconf -u
	ES_HEAP=`free -m |grep Mem | awk '{if ($2/2 >31744)  print 31744;else printf "%.0f", $2/2;}'`
	echo "ES_JAVA_OPTS=\"-Xms${ES_HEAP}m -Xmx${ES_HEAP}m\"" >> /etc/default/elasticsearch
    echo "JAVA_HOME=$JAVA_HOME" >> /etc/default/elasticsearch
    echo 'MAX_OPEN_FILES=65536' >> /etc/default/elasticsearch
    echo 'MAX_LOCKED_MEMORY=unlimited' >> /etc/default/elasticsearch
   
    #https://www.elastic.co/guide/en/elasticsearch/reference/current/setting-system-settings.html#systemd
    mkdir -p /etc/systemd/system/elasticsearch.service.d
    touch /etc/systemd/system/elasticsearch.service.d/override.conf
    echo '[Service]' >> /etc/systemd/system/elasticsearch.service.d/override.conf
    echo 'LimitMEMLOCK=infinity' >> /etc/systemd/system/elasticsearch.service.d/override.conf
    sudo systemctl daemon-reload
   
    chown -R elasticsearch:elasticsearch /usr/share/elasticsearch
    
    if [ ${IS_DATA_NODE} -eq 0 ]; 
    then
        # Kibana    
        IP_ADDRESS=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
        echo "server.host: \"$IP_ADDRESS\"" >> /etc/kibana/kibana.yml
        echo "elasticsearch.url: \"http://$IP_ADDRESS:9200\"" >> /etc/kibana/kibana.yml
        echo "xpack.security.enabled: false" >> /etc/kibana/kibana.yml
        chown -R kibana:kibana /usr/share/kibana
    else
        # data disk
        DATA_DIR="/datadisks/disk1"
        if ! [ -f "vm-disk-utils-0.1.sh" ]; 
        then
            DOWNLOAD_SCRIPT="https://raw.githubusercontent.com/Azure/azure-quickstart-templates/master/shared_scripts/ubuntu/vm-disk-utils-0.1.sh"
            log "Disk setup script not found in `pwd`, download from $DOWNLOAD_SCRIPT"
            wget -q $DOWNLOAD_SCRIPT
        fi
        
        bash ./vm-disk-utils-0.1.sh
        if [ $? -eq 0 ] && [ -d "$DATA_DIR" ];
        then
            log "Disk setup successful, using $DATA_DIR"
            chown -R elasticsearch:elasticsearch $DATA_DIR
            echo "DATA_DIR=$DATA_DIR" >> /etc/default/elasticsearch
        else
            log "Disk setup failed, using default data storage location"
        fi
    fi
}

start_service()
{
	log "Starting Elasticsearch on ${HOSTNAME}"
    systemctl daemon-reload
    systemctl enable elasticsearch.service
    systemctl start elasticsearch.service
    sleep 60
    
    if [ `systemctl is-failed elasticsearch.service` == 'failed' ];
    then
        log "Elasticsearch unit failed to start"
        exit 1
    fi
    
    if [ ${IS_DATA_NODE} -eq 0 ]; 
    then
        log "Starting Kibana on ${HOSTNAME}"
        systemctl enable kibana.service
        systemctl start kibana.service
        sleep 10
    
        if [ `systemctl is-failed kibana.service` == 'failed' ];
        then
            log "Kibana unit failed to start"
            exit 1
        fi    
    fi
}

if [ "${UID}" -ne 0 ];
then
    error "You must be root to run this script."
fi

ES_VERSION="2.3.1"
INSTALL_MARVEL=0
INSTALL_SENSE=0
ELASTICSEARCH_URL="http://localhost:9200"

while getopts :v:t:msh optname; do
  case ${optname} in
    v) ES_VERSION=${OPTARG};;
    m) INSTALL_MARVEL=1;;
    s) INSTALL_SENSE=1;;
    t) ELASTICSEARCH_URL=${OPTARG};; 
    h) help; exit 1;;
   \?) help; error "Option -${OPTARG} not supported.";;
    :) help; error "Option -${OPTARG} requires an argument.";;
  esac
done

log "starting elasticsearch setup"

install_java
install_kibana
install_es
configure_es
configure_system
start_service

log "completed elasticsearch setup"

exit 0
