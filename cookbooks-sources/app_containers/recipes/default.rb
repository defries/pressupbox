include_recipe "bash_for_hipsters"

Chef::Log.info "making containers"

# Load the keys of the items in the 'admins' data bag
apps = data_bag('apps')
Chef::Log.info "found apps: #{apps}"

# Ensure the base folder exists
directory "/data/app_containers" do
  owner "root"
  group "root"
  mode "0755"
  action :create
  recursive true
end

#Ensure root user MySQL credentials are set in /root/.my.cnf
template "/root/.my.cnf" do
  source "my.cnf.erb"
  action :create
  owner "root"
  group "root"
  variables(:user => "root", :password => node['mysql']['server_root_password'])
  mode 0600
end

# Now create an admin & an www user for each app
apps.each do |app_name|
  
  app = data_bag_item('apps', app_name)
  Chef::Log.info "Creating container for app: #{app_name}"
  
  home_dir = "/data/app_containers/#{app_name}"
  admin_user = app_name
  admin_user_uid = app['id_int']
  apache_port = 81
  admin_apache_port = 82
  aliases = app['aliases']
  admin_email = app['admin_email']
  mysql_password = app['mysql_password']

  user(admin_user) do
    uid       admin_user_uid
    group     "www-data"
    comment   "#{app_name} admin user"
 
    home      home_dir
    shell     "/bin/bash"
    supports  :manage_home => true
  end
 
  # admin_user & www_user should have readonly access to the home folder
  directory home_dir do
    owner "root"
    group "root"
    mode "0755"
    action :create
  end

  #Setup SSH authorized keys
  directory "#{home_dir}/.ssh" do
     action :create
     owner admin_user
     group "root"
     mode 0700
  end

  keys = app['authorized_keys']

  template "#{home_dir}/.ssh/authorized_keys" do
    source "authorized_keys.erb"
    action :create
    owner admin_user
    group "root"
    variables(:keys => keys)
    mode 0600
  end  

  # copy in the skeleton structure
  remote_directory home_dir do
    source "skel"
    overwrite true
    files_backup 2
    files_owner admin_user
    files_group 'www-data'
    files_mode "0640"
    owner admin_user
    group 'www-data'
    mode "0750"
  end

  # Bin is a collection of readonly commands the admin_user is allowed to sudo
  directory "#{home_dir}/bin" do
     action :create
     owner "root"
     group "root"
     mode 0755
  end

  #The WWW folders should be +rw for admin_user only
  directory "#{home_dir}/www" do
     action :create
     owner admin_user
     group 'www-data'
     mode 0755
  end

  # make a custom help file
  template "#{home_dir}/help.txt" do
    source "help.txt.erb"
    action :create
    owner "root"
    group "root"
    variables(:admin_user => admin_user)
    mode 0644
  end

  # forward mail to admin_email
  template "#{home_dir}/.forward" do
    source "forward.erb"
    action :create
    owner admin_user
    group 'root'
    variables(:admin_email => admin_email)
    mode 0644
  end

  bash_for_hipsters_bash_for_hipsters "configure cool bash prompt" do
    home_dir home_dir
    username admin_user
    action :create
  end

  # ============================
  # Configure a mysql user
  # ============================
  #http://stackoverflow.com/questions/4528393/mysql-create-user-only-when-the-user-doesnt-exist/5415585#5415585
  execute "Create MySQL user #{admin_user} and grant access to all DBs starting with #{admin_user}_" do
    command "mysql --execute \"GRANT ALL PRIVILEGES ON \\`#{admin_user}_%\\`.* TO '#{admin_user}'@'localhost' IDENTIFIED BY '#{mysql_password}';\""
    action :nothing
  end
  template "#{home_dir}/.my.cnf" do
    source "my.cnf.erb"
    action :create
    owner admin_user
    group "root"
    variables(:user => admin_user, :password => mysql_password)
    mode 0600
    notifies :run, resources(:execute => "Create MySQL user #{admin_user} and grant access to all DBs starting with #{admin_user}_")
  end

  # ============================
  #  Setup app management utils
  # ============================

  template "#{home_dir}/bin/tail-all-logs" do
    source "bin/tail-all-logs.erb"
    action :create
    owner "root"
    group "root"
    variables(:home_dir => home_dir)
    mode 0755
  end

  template "#{home_dir}/bin/process-hosting_setup" do
    source "bin/process-hosting_setup.erb"
    action :create
    owner "root"
    group "root"
    variables(
        :cookbook_paths => Chef::Config[:cookbook_path], 
        :is_solo => Chef::Config[:solo],
        :host_name => node["hostname"], 
        :home_dir => home_dir, 
        :app_name => app_name, 
        :admin_user => admin_user,
        :apache_port => apache_port, 
        :admin_apache_port => admin_apache_port,
        :mysql_password => mysql_password
    ) 
    mode 0755
  end

  ##############################
  # Ensure logs are rotated daily
  ##############################
  logrotate_app "#{admin_user}_apache2_logs" do
    cookbook "logrotate"
    path [ "#{home_dir}/var/log/apache2/access.log", "#{home_dir}/var/log/apache2/error.log" ]
    frequency "daily"
    create "644 #{admin_user} adm"
    rotate 30
  end

  logrotate_app "#{admin_user}_nginx_logs" do
    cookbook "logrotate"
    path [ "#{home_dir}/var/log/nginx/access.log", "#{home_dir}/var/log/nginx/cache-access.log", "#{home_dir}/var/log/nginx/error.log" ]
    frequency "daily"
    create "644 #{admin_user} adm"
    rotate 30
  end

end

#Enable app_container users to run ~/bin/* scripts as sudo
template "/etc/sudoers.d/app_containers" do
  source "sudoers.d-app_containers.erb"
  action :create
  owner "root"
  group "root"
  variables(:app_admin_users => apps)
  mode 0440
end

###############
# Setup each apache2 for each app_container site vhost
###############
template "/etc/apache2/sites-available/include_app_container_vhosts" do
  source "include_app_container_vhosts.erb"
  action :create
  owner "root"
  group "root"
  variables(:app_containers => apps)
  mode 0755
end

link "/etc/apache2/sites-enabled/include_app_container_vhosts" do
  to "../sites-available/include_app_container_vhosts"
end

service "apache2" do
  supports :reload => true
  action [:reload ]
end

service "apache2-mpm-itk" do
  supports :reload => true
  action [:reload ]
end

###############
# Setup nginx as reverse proxy for each apache app server
###############
template "/etc/nginx/sites-available/appcontainers_reverse_proxies" do
  source "nginx/appcontainers_reverse_proxies.erb"
  action :create
  owner "root"
  group "root"
  mode 0755
end

link "/etc/nginx/sites-enabled/appcontainers_reverse_proxies" do
  to "../sites-available/appcontainers_reverse_proxies"
end

service "nginx" do
  supports :reload => true
  action [:reload ]
end


