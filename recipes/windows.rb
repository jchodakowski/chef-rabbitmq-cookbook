#
# Cookbook Name:: rabbitmq
# Recipe:: windows
#
# Copyright 2017, Jason Chodakowski <jchodakowski@me.com>
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
Chef::Recipe.send(:include, Windows::Helper)
erlang_home = win_friendly_path('c:/Program Files/erl7.3')
rabbit_3_3_4_home = win_friendly_path('c:/Program Files (x86)/RabbitMQ Server/rabbitmq_server-3.3.4')
rabbitmq_base = win_friendly_path('c:/RabbitMQ')
rabbitmq_batch = win_friendly_path('c:/Program Files/RabbitMQ Server/rabbitmq_server-3.6.5/sbin/rabbitmq-service.bat')
rabbitmq_plugin = win_friendly_path('c:/Program Files/RabbitMQ Server/rabbitmq_server-3.6.5/sbin/rabbitmq-plugins.bat')

directory rabbitmq_base do
  action :create
  not_if { File.exist?(rabbitmq_base) }
end

previous_erlang = 'Erlang OTP 17 (6.2)'
old_erlang_installed = is_package_installed?(previous_erlang)
windows_package previous_erlang do
  action :remove
  only_if { old_erlang_installed == true }
end

current_erlang = 'Erlang OTP 18 (7.3)'
current_erlang_installed = is_package_installed?(current_erlang)
erlang_is_installed = windows_package current_erlang do
  source node['erlang']['installer.exe']
  action :install
  not_if { current_erlang_installed == true }
end

remove_rabbit_3_3_4 = windows_package 'RabbitMQ Server' do
  version '3.3.4'
  action :remove
  only_if { File.exist?(rabbit_3_3_4_home) }
end

ruby_block 'sleep' do
  block do
    sleep(10)
  end
  only_if { remove_rabbit_3_3_4.updated_by_last_action? }
end

batch 'Set ERLANG_HOME' do
  code <<-EOH
    setx /M ERLANG_HOME "#{erlang_home}"
    EOH
  only_if { erlang_is_installed.updated_by_last_action? }
end

current_rabbitmq = 'RabbitMQ Server 3.6.5'
current_rabbitmq_installed = is_package_installed?(current_rabbitmq)
batch 'Set RabbitMQ env vars' do
  code <<-EOH
    setx /M RABBITMQ_BASE "#{rabbitmq_base}"
    EOH
  not_if { current_rabbitmq_installed == true }
end

windows_package 'RabbitMQ Server' do
  source node['rabbitMQ']['installer.exe']
  version '3.6.5'
  action :install
  installer_type :nsis
  not_if { current_rabbitmq_installed == true }
end

batch 'Install RabbitMQ Service (attempt 1)' do
  code <<-EOH
    set ERLANG_HOME=#{erlang_home}
    set RABBITMQ_BASE=#{rabbitmq_base}
    sc query "RabbitMQ"
    if %ERRORLEVEL% GEQ 1 "#{rabbitmq_batch}" install
    EOH
  not_if { current_rabbitmq_installed == true }
end

presence_plugin_file = win_friendly_path('c:/Program Files/RabbitMQ Server/rabbitmq_server-3.6.5/plugins/rabbit_presence_exchange-3.5.1-20150421.ez')
presence_plugin_installed = remote_file presence_plugin_file do
  source node['rabbitMQ']['plugin']['presence']
  use_conditional_get true
  use_last_modified true
  backup 1
  not_if { current_rabbitmq_installed == true }
end

stamp_plugin_file = win_friendly_path('c:/Program Files/RabbitMQ Server/rabbitmq_server-3.6.5/plugins/rabbitmq_stamp-1.0.2.ez')
stamp_plugin_installed = remote_file stamp_plugin_file do
  source node['rabbitMQ']['plugin']['stamp']
  use_conditional_get true
  use_last_modified true
  backup 1
  not_if { current_rabbitmq_installed == true }
end

# File 'enabled_plugins' won't exist until a plugin has been installed however with previous installs
# a badly named plugin will cause the rest of the process to break so we look for old plugins and delete
# the file first, then allow for the touch to re-add if we need it
enabled_plugin_file = win_friendly_path('c:/RabbitMQ/enabled_plugins')
file enabled_plugin_file do
  action :touch
  not_if { current_rabbitmq_installed == true }
end

batch 'Enable Rabbit Presence Plugin' do
  code <<-EOH
    set ERLANG_HOME=#{erlang_home}
    set RABBITMQ_BASE=#{rabbitmq_base}
    "#{rabbitmq_plugin}" enable rabbit_presence_exchange
    EOH
  notifies :restart, 'service[RabbitMQ]', :immediate
  not_if { current_rabbitmq_installed == true }
  only_if do
    presence_plugin_installed.updated_by_last_action? ||
      File.readlines(enabled_plugin_file).grep(/rabbit_presence_exchange/).empty?
  end
end

batch 'Enable Rabbit Stamp Plugin' do
  code <<-EOH
    set ERLANG_HOME=#{erlang_home}
    set RABBITMQ_BASE=#{rabbitmq_base}
    "#{rabbitmq_plugin}" enable rabbitmq_stamp
    EOH
  notifies :restart, 'service[RabbitMQ]', :immediate
  not_if { current_rabbitmq_installed == true }
  only_if do
    stamp_plugin_installed.updated_by_last_action? ||
      File.readlines(enabled_plugin_file).grep(/rabbitmq_stamp/).empty?
  end
end

batch 'Enable Rabbit Management Plugin' do
  code <<-EOH
    set ERLANG_HOME=#{erlang_home}
    set RABBITMQ_BASE=#{rabbitmq_base}
    "#{rabbitmq_plugin}" enable rabbitmq_management
    EOH
  notifies :restart, 'service[RabbitMQ]', :immediate
  not_if { current_rabbitmq_installed == true }
  only_if { File.readlines(enabled_plugin_file).grep(/rabbitmq_management/).empty? }
end

batch 'Remove RabbitMQ Service' do
  code <<-EOH
    set ERLANG_HOME=#{erlang_home}
    set RABBITMQ_BASE=#{rabbitmq_base}
    "#{rabbitmq_batch}" remove
    EOH
  not_if { current_rabbitmq_installed == true }
end

batch 'Install RabbitMQ Service' do
  code <<-EOH
    set ERLANG_HOME=#{erlang_home}
    set RABBITMQ_BASE=#{rabbitmq_base}
    "#{rabbitmq_batch}" install
  EOH
  notifies :restart, 'service[RabbitMQ]', :immediate
  not_if { current_rabbitmq_installed == true }
  only_if { erlang_is_installed.updated_by_last_action? }
end

service 'RabbitMQ' do
  action :start
  not_if { current_rabbitmq_installed == true }
end
