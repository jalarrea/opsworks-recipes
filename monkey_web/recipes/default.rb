execute 'up-containers' do
    only_if do ::Dir.exists?('/srv/monkey_web') end
    cwd '/srv/monkey_web/'
    command 'docker-compose up -d --build'
    action :nothing
    case node[:platform]
    when 'ubuntu'
      environment 'COMPOSE_API_VERSION' => '1.18'
    end
end

execute 'remove-containers' do
    only_if do ::Dir.exists?('/srv/monkey_web') end
    cwd '/srv/monkey_web/'
    command 'docker-compose rm --force'
    action :nothing
    notifies :run, 'execute[up-containers]', :immediately
    case node[:platform]
    when 'ubuntu'
      environment 'COMPOSE_API_VERSION' => '1.18'
    end
end

execute 'stop-containers' do
    only_if do ::Dir.exists?('/srv/monkey_web') end
    cwd '/srv/monkey_web/'
    command 'docker-compose stop'
    action :nothing
    notifies :run, 'execute[remove-containers]', :immediately
    case node[:platform]
    when 'ubuntu'
      environment 'COMPOSE_API_VERSION' => '1.18'
    end
end

# create docker-compose file
file '/srv/monkey_web/docker-compose.yml' do
    action :nothing
    content lazy { IO.read('/srv/monkey_web/docker-compose-prod.yml') }
    only_if do ::File.exists?('/srv/monkey_web/docker-compose-prod.yml') end
    notifies :run, 'execute[stop-containers]', :immediately
end

# get app
app = search("aws_opsworks_app", "shortname:monkey_web").first
# populate app.env file
ruby_block "insert_line" do
  block do
    app['environment'].each do |env_var|
      file = Chef::Util::FileEdit.new("/srv/monkey_web/app.env")
      file.insert_line_if_no_match("/#{env_var[0]}=#{env_var[1]}/", "#{env_var[0]}=#{env_var[1]}")
      file.write_file
    end
  end
  action :nothing
  notifies :create, 'file[/srv/monkey_web/docker-compose.yml]', :immediately
end

# make sure file app.env exists
file '/srv/monkey_web/app.env' do
  content ''
  action :nothing
  only_if do ::Dir.exists?('/srv/monkey_web') end
  notifies :create, 'ruby_block[insert_line]', :immediately
end

Chef::Log.info("==================#{app['app_source']['ssh_key']}")
# clone repository
application_git '/srv/monkey_web' do
  repository app['app_source']['url']
  revision app['app_source']['revision']
  deploy_key app['app_source']['ssh_key']
  notifies :create, 'file[/srv/monkey_web/app.env]', :immediately
end

# make sure directory exists
# directory '/srv/monkey_web' do
#   action :create
#   notifies :create, 'file[/srv/monkey_web/app.env]', :immediately
#   notifies :create, 'file[/srv/monkey_web/docker-compose.yml]', :immediately
#   notifies :sync, 'application_git[/srv/monkey_web]', :immediately
# end
