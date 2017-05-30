#!/usr/bin/env bash

echo "installing a bunch of prerequisites"
apt-get update
apt-get -y install dnsutils # install dig
apt-get -y install sudo
apt-get -y install adduser curl lsb-base procps zlib1g gzip sysstat ntp bash tree
apt-get -y install python python-support
apt-get -y install apt-transport-https
apt-get -y install unzip
echo "done with prerequisites"

seed_nodes_dns_name=$SEED_NODE_SERVICE

echo "Configuring nodes with the settings:"
echo seed_nodes_dns_name $seed_nodes_dns_name

seed_node_ip=`getent hosts $seed_node_dns_name | awk '{ print $1 }'`
opscenter_ip=`getent hosts $opscenter_dns_name | awk '{ print $1 }'`

node_broadcast_ip=`echo $(hostname -I)`
node_ip=`echo $(hostname -I)`

echo "Configuring nodes with the settings:"
echo seed_node_ip \'$seed_node_ip\'
echo node_broadcast_ip \'$node_broadcast_ip\'
echo node_ip \'$node_ip\'


echo "Installing the Oracle JDK"

# Install add-apt-repository
apt-get -y install software-properties-common

add-apt-repository -y ppa:webupd8team/java
apt-get -y update
echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections
echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections
apt-get -y install oracle-java8-installer

# We're seeing Java installs fail intermittently.  Retrying indefinitely seems problematic.  I'm not sure
# what the correct solution is.  For now, we're just going to run the install a second time.  This will do
# nothing if the first install was successful and I suspect will eliminate the majority of our failures.
apt-get -y install oracle-java8-installer

dse_version=5.0.7-1
opscenter_version=6.1.0

if [ -z "$DSE_VERSION" ]
then
  echo "env \$DSE_VERSION is not set, using default: $dse_version"
else
  echo "env \$DSE_VERSION is set: $DSE_VERSION overiding default"
  dse_version=$DSE_VERSION
fi

echo "Installing DataStax Enterprise"
echo "Adding the DataStax repository"
echo "deb http://datastax%40google.com:8GdeeVT2s7zi@debian.datastax.com/enterprise stable main" | sudo tee -a /etc/apt/sources.list.d/datastax.sources.list


curl -L http://debian.datastax.com/debian/repo_key | sudo apt-key add -
apt-get -y update

echo "Running apt-get install dse"

apt-get -y install dse-full=$dse_version dse=$dse_version dse-hive=$dse_version dse-pig=$dse_version dse-demos=$dse_version dse-libsolr=$dse_version dse-libtomcat=$dse_version dse-libsqoop=$dse_version dse-liblog4j=$dse_version dse-libmahout=$dse_version dse-libhadoop-native=$dse_version dse-libcassandra=$dse_version dse-libhive=$dse_version dse-libpig=$dse_version dse-libhadoop=$dse_version dse-libspark=$dse_version dse-libhadoop2-client-native=$dse_version dse-libgraph=$dse_version dse-libhadoop2-client=$dse_version

# The install of dse creates a cassandra user, so now we can do this:
chown cassandra /mnt
chgrp cassandra /mnt

function config_rack {
  dc="dc0"
  rack=rack1

  file=/etc/dse/cassandra/cassandra-rackdc.properties

  date=$(date +%F)
  backup="$file.$date"
  cp $file $backup

  cat $file \
  | sed -e "s:^\(dc\=\).*:dc\=$dc:" \
  | sed -e "s:^\(rack\=\).*:rack\=$rack:" \
  | sed -e "s:^\(prefer_local\=\).*:rack\=true:" \
  > $file.new

  mv $file.new $file
}

# config_rack

seeds=$seed_node_ip
listen_address=$node_ip
broadcast_address=$node_broadcast_ip
rpc_address="0.0.0.0"
broadcast_rpc_address=$node_broadcast_ip

endpoint_snitch="GossipingPropertyFileSnitch"
num_tokens=64
data_file_directories="/mnt/data"
commitlog_directory="/mnt/commitlog"
saved_caches_directory="/mnt/saved_caches"
phi_convict_threshold=12
auto_bootstrap="false"

file=/etc/dse/cassandra/cassandra.yaml

date=$(date +%F)
backup="$file.$date"
cp $file $backup

cat $file \
| sed -e "s:\(.*- *seeds\:\).*:\1 \"$seeds\":" \
| sed -e "s:[# ]*\(listen_address\:\).*:listen_address\: $listen_address:" \
| sed -e "s:[# ]*\(broadcast_address\:\).*:broadcast_address\: $broadcast_address:" \
| sed -e "s:[# ]*\(rpc_address\:\).*:rpc_address\: $rpc_address:" \
| sed -e "s:[# ]*\(broadcast_rpc_address\:\).*:broadcast_rpc_address\: $broadcast_rpc_address:" \
| sed -e "s:.*\(endpoint_snitch\:\).*:endpoint_snitch\: $endpoint_snitch:" \
| sed -e "s:.*\(num_tokens\:\).*:\1 $num_tokens:" \
| sed -e "s:\(.*- \)/var/lib/cassandra/data.*:\1$data_file_directories:" \
| sed -e "s:.*\(commitlog_directory\:\).*:commitlog_directory\: $commitlog_directory:" \
| sed -e "s:.*\(saved_caches_directory\:\).*:saved_caches_directory\: $saved_caches_directory:" \
| sed -e "s:.*\(phi_convict_threshold\:\).*:phi_convict_threshold\: $phi_convict_threshold:" \
> $file.new

echo "auto_bootstrap: $auto_bootstrap" >> $file.new
echo "" >> $file.new

mv $file.new $file

# Owner was ending up as root which caused the backup service to fail
chown cassandra $file
chgrp cassandra $file

echo "Starting DataStax Enterprise"
sudo service dse start

# 1 hour
sleep 3600

