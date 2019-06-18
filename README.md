# Elasticsearch, X-Pack, VM Scale Sets and Managed Disks

<a href="https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fgithub.com%2Fdaniel06012018%2FDanVMELK%2Fblob%2Fmaster%2Fazuredeploy.json" target="_blank">
    <img src="http://azuredeploy.net/deploybutton.png"/>
</a>

This template deploys an Elasticsearch cluster on Virtual Machines using a Scale Set and managed disks. The template provisions 3 dedicated master nodes, which are in their own availability set with locally attached disks, while the data nodes live in a scale set and use managed disks.

X-Pack is installed on all nodes, and Kibana is installed on the Master-eligible nodes. 

##Notes
Warning! X-Pack security is disabled, and HTTPS is not enabled. The load balancer allows traffic to port 5601 from all sources, so consider updating the network security group to lock this down, or enable X-Pack security, HTTPS and role-based logins. 
