# server-based syntax
# ======================
# Defines a single server with a list of roles and multiple properties.
# You can define all roles on a single server, or split them:

# mainnet-beta
# server "54.85.162.144", user: "ubuntu", roles: %w{primary} #renec-mainnet1
# server "34.233.73.163", user: "ubuntu", roles: %w{primary} #renec-mainnet2
# server "35.153.157.168", user: "ubuntu", roles: %w{primary} #renec-mainnet2-alter
# server "35.169.187.80", user: "ubuntu", roles: %w{primary} #renec-mainnet3
# server "52.6.207.113", user: "ubuntu", roles: %w{primary} #renec-mainnet4
# server "34.233.115.222", user: "ubuntu", roles: %w{primary} #renec-mainnet5
# server "52.21.244.146", user: "ubuntu", roles: %w{primary} #renec-mainnet6
# server "34.228.32.217", user: "ubuntu", roles: %w{primary} #renec-onus
# server "18.234.202.94", user: "ubuntu", roles: %w{primary} #renec-mainnet1-new
# server "54.234.255.164", user: "ubuntu", roles: %w{primary} #renec-mainnet-rpc1
# server "3.225.23.57", user: "ubuntu", roles: %w{primary} #renec-mainnet-rpc2
# server "3.214.105.219", user: "ubuntu", roles: %w{primary} #renec-mainnet-rpc2-copy
# server "44.216.130.82", user: "ubuntu", roles: %w{primary} #renec-mainnet-rpc3
# server "3.219.158.133", user: "ubuntu", roles: %w{primary} #renec-mainnet-rpc3-copy
# server "125.212.234.28", user: "ubuntu", roles: %w{primary} # viettel idc rpc1

# testnet
# server "54.82.166.148", user: "ubuntu", roles: %w{primary} #renec-testnet1
# server "54.226.82.237", user: "ubuntu", roles: %w{primary} #renec-testnet2
# server "100.26.51.186", user: "ubuntu", roles: %w{primary} #renec-testnet3
# server "3.80.218.85", user: "ubuntu", roles: %w{primary} #renec-testnet4
# server "34.235.153.226", user: "ubuntu", roles: %w{primary} #renec-testnet5
# server "52.91.31.100", user: "ubuntu", roles: %w{primary} #renec-testnet6

# devnet
# server "34.233.60.216", user: "ubuntu", roles: %w{primary} #renec-devnet1
# server "34.226.159.53", user: "ubuntu", roles: %w{primary} #renec-devnet2
# server "3.208.204.38", user: "ubuntu", roles: %w{primary} #renec-devnet3
# server "34.231.96.7", user: "ubuntu", roles: %w{primary} #renec-devnet4
# server "44.216.137.217", user: "ubuntu", roles: %w{primary} #renec-devnet5
# server "3.234.33.13", user: "ubuntu", roles: %w{primary} #renec-devnet6
# server "54.172.50.90", user: "ubuntu", roles: %w{primary} #renec-devnet7

# own validator
# server "3.222.98.114", user: "ubuntu", roles: %w{primary}
# server "54.91.199.153", user: "ubuntu", roles: %w{primary}
# server "34.16.149.138", user: "ngocbach", roles: %w{primary} # google console
# server "104.197.81.139", user: "ngocbach", roles: %w{primary} # google console 2
# server "34.42.168.120", user: "ngocbach", roles: %w{primary} # google console 3
server "171.244.62.233", user: "root", roles: %w{primary} # viettel idc

# set :username, "root"
set :home_path, "/home/ubuntu"
set :home_path, "/root"
set :data_full_path, "#{fetch(:home_path)}/renec-cluster"

# set :renec_version, "1.9.29"
# set :renec_version, "1.10.41"
set :renec_version, "1.13.6"
set :is_testnet, true
set :is_devnet, false
# set :is_devnet, true

namespace :deploy do
  after :finishing, :install_all do
    on roles(:primary) do |host|
      within current_path do
        install_renec_tool_suite
        generate_keypairs
        create_renec_service(host.hostname)
        create_renec_sys_tuner_service
        restart_renec_sys_tuner
        start_renec_validator
        setup_log_rotate
      end
    end
  end
end

def install_renec_tool_suite
  execute "rm -rf #{fetch(:home_path)}/.local/share/renec"
  execute "sh -c \"$(curl -sSfL https://renec-release.s3.amazonaws.com/v#{fetch(:renec_version)})\""
  execute "export PATH='#{fetch(:home_path)}/.local/share/renec/install/active_release/bin:$PATH'"

  return puts("Renec installed") if test("[ -d #{fetch(:home_path)}/.config/renec ]")
  execute "sed -i '1 i\\export PATH=\"#{fetch(:home_path)}/.local/share/renec/install/active_release/bin:$PATH\"' #{fetch(:home_path)}/.bashrc"
end

def generate_keypairs
  execute :mkdir, "mkdir -p #{fetch(:data_full_path)}"
  return puts("Keypairs existed") if test("[ -d #{fetch(:data_full_path)}/keypairs ]")

  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-identity.json"
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-vote-account.json"
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-stake-account.json"
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-keygen new --no-passphrase --outfile #{fetch(:data_full_path)}/keypairs/validator-withdrawer.json"
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
  label = "renec_raid"
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

def renec_service_definition(hostname)
  template_path = File.expand_path("../../../coin-service-conf/renec.service.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  start_command = start_renec_validator_command(hostname)
  start_command = start_renec_validator_command_for_testnet(hostname) if fetch(:is_testnet)
  start_command = start_renec_validator_command_for_devnet(hostname) if fetch(:is_devnet)
  namespace = OpenStruct.new(
    start_command: start_command
  )
  template.result(namespace.instance_eval { binding })
end

def create_renec_service(hostname)
  upload! StringIO.new(renec_service_definition(hostname)), "#{current_path}/renec.service"
  execute :sudo, "cp #{current_path}/renec.service /etc/systemd/system/"
end

def start_renec_validator_command_for_testnet(hostname)
  # Do not pass the --no-snapshot-fetch parameter on your initial boot as it's not possible to boot the node all the way
  # from the genesis block. Instead boot from a snapshot first and then add the --no-snapshot-fetch parameter for reboots.
  "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-validator \
    --identity #{fetch(:data_full_path)}/keypairs/validator-identity.json \
    --vote-account #{fetch(:data_full_path)}/keypairs/validator-vote-account.json \
    --ledger #{fetch(:data_full_path)}/ledger \
    --tpu-coalesce-ms 50 \
    --gossip-host #{hostname} \
    --gossip-port 8001 \
    --rpc-port 8888 \
    --enable-rpc-transaction-history \
    --enable-cpi-and-log-storage \
    --dynamic-port-range 8000-8020 \
    --entrypoint 54.91.211.214:8001 \
    --expected-genesis-hash G6N6ysX2TBZyXLAaCFwTTRcizxq2L5dJinKb6WQLkF8W \
    --full-rpc-api \
    --incremental-snapshots \
    --limit-ledger-size 50000000 \
    --account-index program-id \
    --account-index spl-token-owner \
    --account-index spl-token-mint"
end

def start_renec_validator_command_for_devnet(hostname)
  # Do not pass the --no-snapshot-fetch parameter on your initial boot as it's not possible to boot the node all the way
  # from the genesis block. Instead boot from a snapshot first and then add the --no-snapshot-fetch parameter for reboots.
  "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-validator \
    --identity #{fetch(:data_full_path)}/keypairs/validator-identity.json \
    --vote-account #{fetch(:data_full_path)}/keypairs/validator-vote-account.json \
    --ledger #{fetch(:data_full_path)}/ledger \
    --tpu-coalesce-ms 50 \
    --gossip-host #{hostname} \
    --gossip-port 8001 \
    --rpc-port 8888 \
    --enable-rpc-transaction-history \
    --enable-cpi-and-log-storage \
    --dynamic-port-range 8000-8020 \
    --entrypoint 34.233.60.216:8001 \
    --expected-genesis-hash EKEQGSi87pCCMeuZGGA17J8vm8goNKVAANbj8kTWZ841 \
    --incremental-snapshots \
    --wait-for-supermajority 783215 --expected-shred-version 4924 --expected-bank-hash 3dMK1yxqpWBTZ9rDmHJrZtpraoHHwV8EvFyuWwV8J8JS \
    --limit-ledger-size 50000000"
    # --entrypoint 54.172.50.90:8001 \
end

def start_renec_validator_command(hostname)
  # Do not pass the --no-snapshot-fetch parameter on your initial boot as it's not possible to boot the node all the way
  # from the genesis block. Instead boot from a snapshot first and then add the --no-snapshot-fetch parameter for reboots.
  "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-validator \
    --identity #{fetch(:data_full_path)}/keypairs/validator-identity.json \
    --vote-account #{fetch(:data_full_path)}/keypairs/validator-vote-account.json \
    --known-validator 8eHFrtkeZ7dAjRKWN9m9Y8k8f8GbVu4goytXjTKRCSc6 \
    --known-validator 3WsvssMpgNezCGLBQrS6Eb9ostA8AAvTtdnqNyvQQaxH \
    --known-validator 7pgxXXsnZoCLAwXn3kvVrvskmc2keULrJQ3i7iaGEiLE \
    --known-validator j2Udo3QHvbpB44RD7NSYKZhWL8SVuZXzVwbQ6KFnHDa \
    --known-validator 8zmnqf8e1eDX51adYyomxvBWn7bk8bzFb1yBW8m1yqFC \
    --only-known-rpc \
    --ledger #{fetch(:data_full_path)}/ledger \
    --tpu-coalesce-ms 50 \
    --gossip-host #{hostname} \
    --gossip-port 8001 \
    --rpc-port 8888 \
    --enable-rpc-transaction-history \
    --enable-cpi-and-log-storage \
    --require-tower \
    --dynamic-port-range 8000-8020 \
    --entrypoint entrypoint1-mainnet-beta.renec.foundation:8001 \
    --entrypoint 35.169.187.80:8001 \
    --entrypoint entrypoint2-mainnet-beta.renec.foundation:8001 \
    --entrypoint entrypoint3-mainnet-beta.renec.foundation:8001 \
    --entrypoint 52.21.244.146:8001 \
    --expected-genesis-hash 7PNFRHLxT9FcAxSUcg3P8BraJnnUBnjuy8LwRbRJvVkX \
    --incremental-snapshots \
    --limit-ledger-size 50000000"
    # --account-index program-id \
    # --account-index spl-token-owner \
    # --account-index spl-token-mint"
    # --full-rpc-api \
end

def renec_log_rotate_config
  template_path = File.expand_path("../../../coin-conf/log-rotate.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  namespace = OpenStruct.new(
    data_path: fetch(:data_full_path)
  )
  template.result(namespace.instance_eval { binding })
end

def setup_log_rotate
  upload! StringIO.new(renec_log_rotate_config), "#{current_path}/log-rotate"
  execute :sudo, "cp #{current_path}/log-rotate /etc/logrotate.d/renec"
end

def start_renec_validator
  execute :sudo, "systemctl stop renec.service"
  # dangerous command
  # execute "rm -rf #{fetch(:home_path)}/renec-cluster/ledger" if fetch(:is_devnet)
  execute :sudo, "systemctl enable renec.service"
  execute :sudo, "systemctl restart renec.service"
end

def renec_sys_tuner_service_definition
  template_path = File.expand_path("../../../coin-service-conf/renec-sys-tuner.service.erb", __FILE__)
  template = ERB.new(File.read(template_path))
  start_command = "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec-sys-tuner --user #{fetch(:username)}"
  namespace = OpenStruct.new(
    start_command: start_command
  )
  template.result(namespace.instance_eval { binding })
end

def create_renec_sys_tuner_service
  upload! StringIO.new(renec_sys_tuner_service_definition), "#{current_path}/renec-sys-tuner.service"
  execute :sudo, "cp #{current_path}/renec-sys-tuner.service /etc/systemd/system/"
end

def restart_renec_sys_tuner
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec config set --url mainnet-beta"
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec config set --url testnet" if fetch(:is_testnet)
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec config set --url devnet" if fetch(:is_devnet)
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec config set --keypair #{fetch(:home_path)}/renec-cluster/keypairs/validator-identity.json"
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec address -k #{fetch(:home_path)}/renec-cluster/keypairs/validator-identity.json"
  execute :sudo, "systemctl enable renec-sys-tuner.service"
  execute :sudo, "systemctl restart renec-sys-tuner.service"
end

def start_renec_validator_custom
  execute "echo Remi2023@ | sudo -S systemctl stop renec.service"
  # dangerous command
  # execute "rm -rf #{fetch(:home_path)}/renec-cluster/ledger" if fetch(:is_devnet)
  execute "echo Remi2023@ | sudo -S systemctl enable renec.service"
  execute "echo Remi2023@ | sudo -S systemctl restart renec.service"
end

def restart_renec_sys_tuner_custom
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec config set --url mainnet-beta"
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec config set --url testnet" if fetch(:is_testnet)
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec config set --url devnet" if fetch(:is_devnet)
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec config set --keypair #{fetch(:home_path)}/renec-cluster/keypairs/validator-identity.json"
  execute "#{fetch(:home_path)}/.local/share/renec/install/active_release/bin/renec address -k #{fetch(:home_path)}/renec-cluster/keypairs/validator-identity.json"
  # execute :sudo, "systemctl enable renec-sys-tuner.service"
  # execute :sudo, "systemctl restart renec-sys-tuner.service"
  execute "echo Remi2023@ | sudo -S systemctl enable renec-sys-tuner.service"
  execute "echo Remi2023@ | sudo -S systemctl restart renec-sys-tuner.service"
end

def setup_log_rotate_custom
  upload! StringIO.new(renec_log_rotate_config), "#{current_path}/log-rotate"
  # execute :sudo, "cp #{current_path}/log-rotate /etc/logrotate.d/renec"
  execute "echo Remi2023@ | sudo -S cp #{current_path}/log-rotate /etc/logrotate.d/renec"
end

def create_renec_sys_tuner_service_custom
  upload! StringIO.new(renec_sys_tuner_service_definition), "#{current_path}/renec-sys-tuner.service"
  # execute :sudo, "cp #{current_path}/renec-sys-tuner.service /etc/systemd/system/"
  execute "echo Remi2023@ | sudo -S cp #{current_path}/renec-sys-tuner.service /etc/systemd/system/"
end

def create_renec_service_custom(hostname)
  upload! StringIO.new(renec_service_definition(hostname)), "#{current_path}/renec.service"
  # execute :sudo, "cp #{current_path}/renec.service /etc/systemd/system/"
  execute "echo Remi2023@ | sudo -S cp #{current_path}/renec.service /etc/systemd/system/"
end
