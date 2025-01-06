# server-based syntax
# ======================
# Defines a single server with a list of roles and multiple properties.
# You can define all roles on a single server, or split them:

# server "3.215.77.187", user: "ubuntu", roles: %w{primary}
# server "54.198.98.25", user: "ubuntu", roles: %w{primary}
# server "3.239.94.146", user: "ubuntu", roles: %w{primary}
# server "44.200.180.55", user: "ubuntu", roles: %w{primary}
# server "100.27.236.246", user: "ubuntu", roles: %w{primary}
# server "34.229.114.102", user: "ubuntu", roles: %w{primary}
server "44.192.92.64", user: "ubuntu", roles: %w{primary}

set :home_path, "/home/ubuntu"
set :data_full_path, "#{fetch(:home_path)}/solana-cluster"

set :solana_version, "1.18.15"
set :is_testnet, false
set :is_devnet, false

namespace :deploy do
  after :finishing, :install_all do
    on roles(:primary) do |host|
      within current_path do
        install_solana_tool_suite
        generate_keypairs
        create_solana_service(host.hostname)
        create_solana_sys_tuner_service
        restart_solana_sys_tuner
        start_solana_validator
        setup_log_rotate
        # setup_prometheus
        # create_node_exporter_service
        # create_prometheus_service("Solana RPC")
      end
    end
  end
end

def setup_prometheus
  # execute "wget https://github.com/prometheus/prometheus/releases/download/v2.51.0/prometheus-2.51.0.linux-amd64.tar.gz"
  # execute "tar xvfz prometheus-2.51.0.linux-amd64.tar.gz"
  # execute "mv prometheus-2.51.0.linux-amd64 prometheus"
  # execute "wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-amd64.tar.gz"
  # execute "tar xvfz node_exporter-1.7.0.linux-amd64.tar.gz"
  # execute "mv node_exporter-1.7.0.linux-amd64 node-exporter"
  execute "wget https://github.com/prometheus/prometheus/releases/download/v2.51.0/prometheus-2.51.0.linux-arm64.tar.gz"
  execute "tar xvfz prometheus-2.51.0.linux-arm64.tar.gz"
  execute "mv prometheus-2.51.0.linux-arm64 prometheus"
  execute "wget https://github.com/prometheus/node_exporter/releases/download/v1.7.0/node_exporter-1.7.0.linux-arm64.tar.gz"
  execute "tar xvfz node_exporter-1.7.0.linux-arm64.tar.gz"
  execute "mv node_exporter-1.7.0.linux-arm64 node-exporter"
end

def install_solana_tool_suite
  execute "rm -rf #{fetch(:home_path)}/.local/share/solana"
  execute "sh -c \"$(curl -sSfL https://release.solana.com/v#{fetch(:solana_version)}/install)\""
  execute "export PATH='#{fetch(:home_path)}/.local/share/solana/install/active_release/bin:$PATH'"

  return puts("Solana installed") if test("[ -d #{fetch(:home_path)}/.config/solana ]")
  execute "sed -i '1 i\\export PATH=\"#{fetch(:home_path)}/.local/share/solana/install/active_release/bin:$PATH\"' #{fetch(:home_path)}/.bashrc"
end

def generate_keypairs
  execute :mkdir, "mkdir -p #{fetch(:data_full_path)}"
  return puts("Keypairs existed") if test("[ -d #{fetch(:data_full_path)}/keypairs ]")

  execute "#{fetch(:home_path)}/.local/share/solana/install/active_release/bin/solana-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-identity.json"
  execute "#{fetch(:home_path)}/.local/share/solana/install/active_release/bin/solana-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-vote-account.json"
  execute "#{fetch(:home_path)}/.local/share/solana/install/active_release/bin/solana-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-stake-account.json"
  execute "#{fetch(:home_path)}/.local/share/solana/install/active_release/bin/solana-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-withdrawer.json"
end

def install_nvme
  return puts("Nvme installed") if test("[ -d #{fetch(:data_full_path)} ]")

  # ssh to server and run lsblk to get the device name
  devices = [
    "/dev/nvme1n1",
    "/dev/nvme2n1",
    "/dev/nvme3n1",
    "/dev/nvme4n1"
  ]
  label = "solana_raid"
  execute :sudo, "mdadm --create --verbose /dev/md0 --level=0 --name=#{label} --raid-devices=#{devices.size} #{devices.join(' ')}"
  execute :sudo, "mkfs.ext4 -F -L #{label} /dev/md0"
  execute :sudo, "mkfs.ext4 -F -L #{label} /dev/nvme1n1"
  execute :sudo, "mdadm --detail --scan | sudo tee -a /etc/mdadm/mdadm.conf"
  execute :sudo, "update-initramfs -u"
  execute :mkdir, "mkdir -p #{fetch(:data_full_path)}"
  execute :sudo, "mount LABEL=#{label} #{fetch(:data_full_path)}"
  execute :sudo, "bash -c 'echo LABEL=#{label}       #{fetch(:data_full_path)}   ext4    defaults,nofail        0       2  >> /etc/fstab'"
  execute :sudo, "chown #{fetch(:username)}:#{fetch(:username)} #{fetch(:data_full_path)}"
end

# def install_storage_without_nvme
#   return puts("Storage installed") if test("[ -d #{fetch(:data_full_path)} ]")
#   execute :mkdir, "mkdir -p #{fetch(:data_full_path)}"
#   execute :sudo, "bash -c 'echo LABEL=#{label}       #{fetch(:data_full_path)}   ext4    defaults,nofail        0       2  >> /etc/fstab'"
#   execute :sudo, "chown #{fetch(:username)}:#{fetch(:username)} #{fetch(:data_full_path)}"
# end

def solana_service_definition(hostname)
  template_path = File.expand_path("../../../coin-service-conf/solana.service.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  start_command = start_solana_validator_command(hostname)
  # start_command = start_solana_validator_command_testnet(hostname)
  namespace = OpenStruct.new(
    start_command: start_command
  )
  template.result(namespace.instance_eval { binding })
end

def create_solana_service(hostname)
  upload! StringIO.new(solana_service_definition(hostname)), "#{current_path}/solana.service"
  execute :sudo, "cp #{current_path}/solana.service /etc/systemd/system/"
end

def start_solana_validator_command_testnet(hostname)
  # Do not pass the --no-snapshot-fetch parameter on your initial boot as it's not possible to boot the node all the way
  # from the genesis block. Instead boot from a snapshot first and then add the --no-snapshot-fetch parameter for reboots.
  first_start = !test("[ -d #{fetch(:data_full_path)}/snapshot/ ]")
  "/home/ubuntu/.local/share/solana/install/active_release/bin/solana-validator \
    --identity #{fetch(:data_full_path)}/keypairs/validator-identity.json \
    --ledger #{fetch(:data_full_path)}/ledger \
    --no-voting \
    --private-rpc \
    --rpc-port 8888 \
    --dynamic-port-range 8000-8020 \
    --snapshot-interval-slots 5000 \
    --incremental-snapshots \
    --entrypoint entrypoint.mainnet-beta.solana.com:8001 \
    --entrypoint entrypoint2.mainnet-beta.solana.com:8001 \
    --entrypoint entrypoint3.mainnet-beta.solana.com:8001 \
    --entrypoint entrypoint4.mainnet-beta.solana.com:8001 \
    --entrypoint entrypoint5.mainnet-beta.solana.com:8001 \
    --expected-genesis-hash 5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d \
    --wal-recovery-mode skip_any_corrupted_record \
    --limit-ledger-size #{first_start ? "" : "--no-snapshot-fetch"}"
end

def start_solana_validator_command(hostname)
  # Do not pass the --no-snapshot-fetch parameter on your initial boot as it's not possible to boot the node all the way
  # from the genesis block. Instead boot from a snapshot first and then add the --no-snapshot-fetch parameter for reboots.
  first_start = !test("[ -d #{fetch(:data_full_path)}/snapshot/ ]")
  "/home/ubuntu/.local/share/solana/install/active_release/bin/solana-validator \
    --identity #{fetch(:data_full_path)}/keypairs/validator-identity.json \
    --known-validator 7Np41oeYqPefeNQEHSv1UDhYrehxin3NStELsSKCT4K2 \
    --known-validator GdnSyH3YtwcxFvQrVVJMm1JhTS4QVX7MFsX56uJLUfiZ \
    --known-validator DE1bawNcRJB9rVm3buyMVfr8mBEoyyu73NBovf2oXJsJ \
    --known-validator CakcnaRDHka2gXyfbEd2d3xsvkJkqsLw2akB3zsN1D2S \
    --only-known-rpc \
    --expected-shred-version 11762 \
    --ledger #{fetch(:data_full_path)}/ledger \
    --no-voting \
    --private-rpc \
    --rpc-port 8888 \
    --dynamic-port-range 8000-8020 \
    --snapshot-interval-slots 5000 \
    --incremental-snapshots \
    --entrypoint entrypoint.mainnet-beta.solana.com:8001 \
    --entrypoint entrypoint2.mainnet-beta.solana.com:8001 \
    --entrypoint entrypoint3.mainnet-beta.solana.com:8001 \
    --entrypoint entrypoint4.mainnet-beta.solana.com:8001 \
    --entrypoint entrypoint5.mainnet-beta.solana.com:8001 \
    --expected-genesis-hash 5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d \
    --wal-recovery-mode skip_any_corrupted_record \
    --limit-ledger-size #{first_start ? "" : "--no-snapshot-fetch"}"
end
    # --full-rpc-api \

def solana_log_rotate_config
  template_path = File.expand_path("../../../coin-conf/log-rotate.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  namespace = OpenStruct.new(
    data_path: fetch(:data_full_path)
  )
  template.result(namespace.instance_eval { binding })
end

def setup_log_rotate
  upload! StringIO.new(solana_log_rotate_config), "#{current_path}/log-rotate"
  execute :sudo, "cp #{current_path}/log-rotate /etc/logrotate.d/solana"
end

def start_solana_validator
  execute :sudo, "systemctl stop solana.service"
  # dangerous command
  # execute "rm -rf #{fetch(:home_path)}/solana-cluster/ledger" if fetch(:is_devnet)
  execute :sudo, "systemctl enable solana.service"
  execute :sudo, "systemctl restart solana.service"
end

def solana_sys_tuner_service_definition
  template_path = File.expand_path("../../../coin-service-conf/solana-sys-tuner.service.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  start_command = "#{fetch(:home_path)}/.local/share/solana/install/active_release/bin/solana-sys-tuner --user #{fetch(:username)}"
  namespace = OpenStruct.new(
    start_command: start_command
  )
  template.result(namespace.instance_eval { binding })
end

def create_solana_sys_tuner_service
  upload! StringIO.new(solana_sys_tuner_service_definition), "#{current_path}/solana-sys-tuner.service"
  execute :sudo, "cp #{current_path}/solana-sys-tuner.service /etc/systemd/system/"
end

def node_exporter_service_definition
  template_path = File.expand_path("../../../coin-service-conf/node-exporter.service.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  template.result
end

def create_node_exporter_service
  upload! StringIO.new(node_exporter_service_definition), "#{current_path}/node-exporter.service"
  execute :sudo, "cp #{current_path}/node-exporter.service /etc/systemd/system/"
  execute :sudo, "systemctl enable node-exporter.service"
  execute :sudo, "systemctl restart node-exporter.service"
end

def prometheus_service_definition
  template_path = File.expand_path("../../../coin-service-conf/prometheus.service.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  template.result
end

def create_prometheus_service(node_name)
  upload! StringIO.new(prometheus_config(node_name)), "#{current_path}/prometheus.yml"
  execute "cp #{current_path}/prometheus.yml /home/ubuntu/prometheus/prometheus.yml"

  upload! StringIO.new(prometheus_service_definition), "#{current_path}/prometheus.service"
  execute :sudo, "cp #{current_path}/prometheus.service /etc/systemd/system/"
  execute :sudo, "systemctl enable prometheus.service"
  execute :sudo, "systemctl restart prometheus.service"
end

def prometheus_config(job_name)
  template_path = File.expand_path("../../../coin-conf/prometheus.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  namespace = OpenStruct.new(
    job_name: job_name
  )
  template.result(namespace.instance_eval { binding })
end

def restart_solana_sys_tuner
  execute "#{fetch(:home_path)}/.local/share/solana/install/active_release/bin/solana config set --url mainnet-beta"
  execute "#{fetch(:home_path)}/.local/share/solana/install/active_release/bin/solana config set --url testnet" if fetch(:is_testnet)
  execute "#{fetch(:home_path)}/.local/share/solana/install/active_release/bin/solana config set --url devnet" if fetch(:is_devnet)
  execute "#{fetch(:home_path)}/.local/share/solana/install/active_release/bin/solana config set --keypair #{fetch(:home_path)}/solana-cluster/keypairs/validator-identity.json"
  execute "#{fetch(:home_path)}/.local/share/solana/install/active_release/bin/solana address -k #{fetch(:home_path)}/solana-cluster/keypairs/validator-identity.json"
  execute :sudo, "systemctl enable solana-sys-tuner.service"
  execute :sudo, "systemctl restart solana-sys-tuner.service"
end
