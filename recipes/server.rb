#/postgresql.conf.
# Cookbook Name:: postgresql
# Recipe:: server
#
# Author:: Joshua Timberman (<joshua@opscode.com>)
# Author:: Lamont Granquist (<lamont@opscode.com>)
# Copyright 2009-2011, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
#

include_recipe "simple_iptables"

# Allow postgres
simple_iptables_rule "system" do
  rule ["--proto tcp -m state --state NEW -s 10.0.0.0/8 --dport 5432"]
  jump "ACCEPT"
end

directory "/raiddisk/postgresql" do
  owner "root"
  group "root"
  mode "0755"
  action :create
end

link "/var/lib/postgresql" do
 to "#{node['postgresql']['bind_dir']}/postgresql"
end

include_recipe "postgresql::client"

postgres_pass = Chef::EncryptedDataBagItem.load("passwords", "postgresql")["password"]

case node[:postgresql][:version]
when "8.3"
  node.default[:postgresql][:ssl] = "off"
when "8.4"
  node.default[:postgresql][:ssl] = "true"
when "9.1"
  node.default[:postgresql][:ssl] = "true"
end

# Include the right "family" recipe for installing the server
# since they do things slightly differently.
case node.platform
when "redhat", "centos", "fedora", "suse", "scientific", "amazon"
  include_recipe "postgresql::server_redhat"
when "debian", "ubuntu"
  include_recipe "postgresql::server_debian"
end

pg_hba_conf_source = begin
  if node[:postgresql][:version] == "9.1"
    "pg_hba_91.conf.erb"
  else
    "pg_hba.conf.erb"
  end
end
template "#{node[:postgresql][:dir]}/pg_hba.conf" do
  source pg_hba_conf_source
  owner "postgres"
  group "postgres"
  mode 0600
  notifies :reload, resources(:service => "postgresql"), :immediately
end

# Default PostgreSQL install has 'ident' checking on unix user 'postgres'
# and 'md5' password checking with connections from 'localhost'. This script
# runs as user 'postgres', so we can execute the 'role' and 'database' resources
# as 'root' later on, passing the below credentials in the PG client.
bash "assign-postgres-password" do
  user 'postgres'
  code <<-EOH
echo "ALTER ROLE postgres ENCRYPTED PASSWORD '#{postgres_pass}';" | psql
  EOH
  only_if "invoke-rc.d postgresql status | grep main" # make sure server is actually running
  not_if do
    begin
      require 'rubygems'
      Gem.clear_paths
      require 'pg'
      conn = PGconn.connect("localhost", 5432, nil, nil, nil, "postgres", postgres_pass)
    rescue PGError
      false
    end
  end
  action :run
end
