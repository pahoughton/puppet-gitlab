# Class:: gitlab::install
#
#
## Manual actions required until gitlab package is fixed.
#
# fixme - repo directory was set wrong in gitlab/config/gitlab.yml
#
# edit Gemfile* as described at:
# http://stackoverflow.com/questions/22825497/installing-gitlab-missing-modernizer/22827382#22827382
# su git - -c 'bundle install --without development --without mysqlclientlib aws test --deployment'
# su git - -c 'bundle exec rake db:migrate RAILS_ENV=production'
# su git - -c 'bundle exec rake assets:clean assets:precompile cache:clear RAILS_ENV=production'
# /usr/bin/yes yes | su git - -c 'bundle exec rake gitlab:setup RAILS_ENV=production'
#
#
class gitlab::install inherits gitlab {

  $gitlab_without_gems = $gitlab_dbtype ? {
    'mysql' => 'postgres',
    'pgsql' => 'mysqlclientlib',
    default => '',
  }

  Exec {
    user => $git_user,
    path => $exec_path,
  }

  File {
    owner => $git_user,
    group => $git_user,
  }

  file { "${git_home}/gitlab/modernizr-2.6.2.gem" :
    ensure  => file,
    source  => 'puppet:///modules/gitlab/modernizr-2.6.2.gem',
    require => File[$git_home],
  }
  # gitlab shell
  file { "${git_home}/gitlab-shell/config.yml":
    ensure  => file,
    content => template('gitlab/gitlab-shell.config.yml.erb'),
    mode    => '0644',
    require => File[$git_home],
  }

  exec { 'install gitlab-shell':
    command => "ruby ${git_home}/gitlab-shell/bin/install",
    cwd     => $git_home,
    creates => "${gitlab_repodir}/repositories",
    require => File["${git_home}/gitlab-shell/config.yml"],
  }

  # gitlab
  file { "${git_home}/gitlab/config/database.yml":
    ensure  => file,
    content => template('gitlab/database.yml.erb'),
    mode    => '0640',
    require => File[$git_home],
  }

  file { "${git_home}/gitlab/config/unicorn.rb":
    ensure  => file,
    content => template('gitlab/unicorn.rb.erb'),
    require => File[$git_home],
  }

  file { "${git_home}/gitlab/config/gitlab.yml":
    ensure  => file,
    content => template('gitlab/gitlab.yml.erb'),
    mode    => '0640',
    require => File[$git_home],
  }

  file { "${git_home}/gitlab/config/resque.yml":
    ensure  => file,
    content => template('gitlab/resque.yml.erb'),
    require => File[$git_home],
  }

  file { "${git_home}/gitlab/config/initializers/rack_attack.rb":
    ensure  => file,
    source  => "${git_home}/gitlab/config/initializers/rack_attack.rb.example",
    require => File[$git_home],
  }

  if $gitlab_relative_url_root {
    file { "${git_home}/gitlab/config/application.rb":
      ensure  => file,
      content => template('gitlab/application.rb.erb'),
      require => File[$git_home],
    }
  }

  exec { 'install gitlab':
    command => "bundle install --without development aws test ${gitlab_without_gems} ${gitlab_bundler_flags}",
    cwd     => "${git_home}/gitlab",
    unless  => 'bundle check',
    timeout => 0,
    require => [
      File["${git_home}/gitlab/config/database.yml"],
      File["${git_home}/gitlab/config/unicorn.rb"],
      File["${git_home}/gitlab/config/gitlab.yml"],
      File["${git_home}/gitlab/config/resque.yml"],
    ],
    notify  => Exec['run migrations'],
  }

  exec { 'setup gitlab database':
    command => '/usr/bin/yes yes | bundle exec rake gitlab:setup RAILS_ENV=production',
    cwd     => "${git_home}/gitlab",
    creates => "${git_home}/.gitlab_setup_done",
    require => Exec['install gitlab'],
    notify  => Exec['precompile assets'],
    before  => Exec['run migrations'],
  }

  exec { 'precompile assets':
    command     => 'bundle exec rake assets:clean assets:precompile cache:clear RAILS_ENV=production',
    cwd         =>  "${git_home}/gitlab",
    refreshonly =>  true,
  }

  exec { 'run migrations':
    command     => 'bundle exec rake db:migrate RAILS_ENV=production',
    cwd         =>  "${git_home}/gitlab",
    refreshonly =>  true,
    notify      => Exec['precompile assets'],
  }

  file {
    "${git_home}/.gitlab_setup_done":
      ensure  => present,
      owner   => 'root',
      group   => 'root',
      require => Exec['setup gitlab database'];
  }

}
