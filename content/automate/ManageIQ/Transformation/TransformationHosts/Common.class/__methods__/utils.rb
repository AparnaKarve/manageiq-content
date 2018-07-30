module ManageIQ
  module Automate
    module Transformation
      module TransformationHosts
        module Common
          class Utils
            def initialize(handle = $evm)
              @debug = true
              @handle = handle
            end

            def main
            end

            def self.get_runners_count_by_host(host, handle = $evm)
              handle.vmdb(:service_template_transformation_plan_task).where(:state => 'active').select { |task| task.get_option(:transformation_host_id) == host.id }.size
            end

            def self.transformation_hosts(ems, factory_config)
              thosts = []
              ems.hosts.each do |host|
                next unless host.tagged_with?('v2v_transformation_host', 'true')
                thosts << {
                  :type                  => 'OVirtHost',
                  :transformation_method => host.tags('v2v_transformation_method'),
                  :host                  => host,
                  :runners               => {
                    :current => get_runners_count_by_host(host),
                    :maximum => host.custom_get('Max Transformation Runners') || factory_config['transformation_host_max_runners'] || 10
                  }
                }
              end
              thosts.sort_by! { |th| th[:runners][:current] }
            end

            def self.eligible_transformation_hosts(ems, factory_config)
              transformation_hosts(ems, factory_config).select { |thost| thost[:runners][:current] < thost[:runners][:maximum] }
            end

            def self.get_runners_count_by_ems(ems, factory_config)
              transformation_hosts(ems, factory_config).inject(0) { |sum, thost| sum + thost[:runners][:current] }
            end

            def self.get_transformation_host(task, factory_config, handle = $evm)
              ems = handle.vmdb(:ext_management_system).find_by(:id => task.get_option(:destination_ems_id))
              ems_max_runners = ems.custom_get('Max Transformation Runners').to_i || factory_config['ems_max_runners'] || 1
              ems_cur_runners = get_runners_count_by_ems(ems, factory_config)
              transformation_host_hash = ems_cur_runners < ems_max_runners ? eligible_transformation_hosts(ems, factory_config).first : {}
              return transformation_host_hash[:type], transformation_host_hash[:host], transformation_host_hash[:transformation_method]
            end

            def self.virtv2vwrapper_options(task)
              send("virtv2vwrapper_options_#{task.get_option(:transformation_type)}_#{task.get_option(:transformation_method)}", task)
            end

            def self.remote_command(task, transformation_host, command, stdin = nil, run_as = nil)
              "ManageIQ::Automate::Transformation::TransformationHosts::#{task.get_option(:transformation_host_type)}::Utils".constantize.remote_command(transformation_host, command, stdin, run_as)
            end

            def self.virtv2vwrapper_options_vmwarews2rhevm_vddk(task)
              source_vm = task.source
              source_ems = source_vm.ext_management_system
              source_cluster = source_vm.ems_cluster

              destination_cluster = task.transformation_destination(source_cluster)
              destination_ems = destination_cluster.ext_management_system
              destination_storage = task.transformation_destination(source_vm.hardware.disks.select { |d| d.device_type == 'disk' }.first.storage)

              vmware_uri = "vpx://"
              vmware_uri += "#{source_ems.authentication_userid.gsub('@', '%40')}@#{source_ems.hostname}/"
              vmware_uri += "#{source_cluster.v_parent_datacenter.gsub(' ', '%20')}/#{source_cluster.name.gsub(' ', '%20')}/#{source_vm.host.uid_ems}"
              vmware_uri += "?no_verify=1"

              {
                :vm_name             => source_vm.name,
                :transport_method    => 'vddk',
                :vmware_fingerprint  => ManageIQ::Automate::Transformation::Infrastructure::VM::VMware::Utils.get_vcenter_fingerprint(source_ems),
                :vmware_uri          => vmware_uri,
                :vmware_password     => source_ems.authentication_password,
                :rhv_url             => "https://#{destination_ems.hostname}/ovirt-engine/api",
                :rhv_cluster         => destination_cluster.name,
                :rhv_storage         => destination_storage.name,
                :rhv_password        => destination_ems.authentication_password,
                :source_disks        => task[:options][:virtv2v_disks].map { |disk| disk[:path] },
                :network_mappings    => task[:options][:virtv2v_networks],
                :install_drivers     => true,
                :insecure_connection => true
              }
            end

            def self.virtv2vwrapper_options_vmwarews2rhevm_ssh(task)
              source_vm = task.source
              source_cluster = source_vm.ems_cluster
              source_storage = source_vm.hardware.disks.select { |d| d.device_type == 'disk' }.first.storage

              destination_cluster = task.transformation_destination(source_cluster)
              destination_ems = destination_cluster.ext_management_system
              destination_storage = task.transformation_destination(source_vm.hardware.disks.select { |d| d.device_type == 'disk' }.first.storage)

              {
                :vm_name             => "ssh://root@#{source_vm.host.ipaddress}/vmfs/volumes/#{source_storage.name}/#{source_vm.location}",
                :transport_method    => 'ssh',
                :rhv_url             => "https://#{destination_ems.hostname}/ovirt-engine/api",
                :rhv_cluster         => destination_cluster.name,
                :rhv_storage         => destination_storage.name,
                :rhv_password        => destination_ems.authentication_password,
                :source_disks        => task[:options][:virtv2v_disks].map { |disk| disk[:path] },
                :network_mappings    => task[:options][:virtv2v_networks],
                :install_drivers     => true,
                :insecure_connection => true
              }
            end

            private_class_method(:virtv2vwrapper_options_vmwarews2rhevm_vddk, :virtv2vwrapper_options_vmwarews2rhevm_ssh)
          end
        end
      end
    end
  end
end

if $PROGRAM_NAME == __FILE__
  ManageIQ::Automate::Transformation::TransformationHosts::Common::Utils.new.main
end
