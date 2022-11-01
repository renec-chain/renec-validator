require 'sinatra'

set :port, 65534

get '/disk_space_usage' do
  `df -h`
end

get '/host_info' do
  `lsb_release -a`
end
