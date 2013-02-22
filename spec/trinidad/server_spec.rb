require File.expand_path('../spec_helper', File.dirname(__FILE__))
require 'fileutils'

describe Trinidad::Server do
  include FakeApp
  
  JSystem = java.lang.System
  JContext = javax.naming.Context
  
  before { Trinidad.configure }
  after  { Trinidad.configuration = nil }

  after { FileUtils.rm_rf( File.expand_path('../../ssl', File.dirname(__FILE__)) ) rescue nil }

  APP_STUBS_DIR = File.expand_path('../stubs', File.dirname(__FILE__))

  before do 
    FileUtils.mkdir(APP_STUBS_DIR) unless File.exists?(APP_STUBS_DIR)
  end
  after { FileUtils.rm_r APP_STUBS_DIR }

  it "always uses symbols as configuration keys" do
    Trinidad.configure { |c| c.port = 4000 }
    server = configured_server
    server.config[:port].should == 4000
  end

  it "enables catalina naming" do
    expect( configured_server.tomcat ).to_not be nil
    JSystem.get_property(JContext.URL_PKG_PREFIXES).should  include("org.apache.naming")
    JSystem.get_property(JContext.INITIAL_CONTEXT_FACTORY).should == "org.apache.naming.java.javaURLContextFactory"
    JSystem.get_property("catalina.useNaming").should == "true"
  end

  it "disables ssl when config param is nil" do
    server = configured_server
    server.ssl_enabled?.should be false
  end

  it "disables ajp when config param is nil" do
    server = configured_server
    server.ajp_enabled?.should be false
  end

  it "enables ssl when config param is a number" do
    server = configured_server({
      :ssl => { :port => 8443 },
      :web_app_dir => MOCK_WEB_APP_DIR
    })

    server.ssl_enabled?.should be true
    #File.exist?('ssl').should be true
  end

  it "enables ajp when config param is a number" do
    server = configured_server( :ajp => { :port => 8009 } )
    server.ajp_enabled?.should be_true
  end

  it "includes a connector with https scheme when ssl is enabled" do
    Trinidad.configure do |c|
      c.ssl = {:port => 8443}
    end
    server = configured_server

    connectors = server.tomcat.service.find_connectors
    connectors.should have(1).connector
    connectors[0].scheme.should == 'https'
  end

  it "includes a connector with protocol AJP when ajp is enabled" do
    Trinidad.configure do |c|
      c.ajp = {:port => 8009}
    end
    server = configured_server

    connectors = server.tomcat.service.find_connectors
    connectors.should have(1).connector
    connectors[0].protocol.should == 'AJP/1.3'
  end

  it "loads one application for each option present into :web_apps" do
    server = configured_server({
      :web_apps => {
        :_ock1 => {
          :context_path => '/mock1',
          :web_app_dir => MOCK_WEB_APP_DIR
        },
        :mock2 => {
          :web_app_dir => MOCK_WEB_APP_DIR
        },
        :default => {
          :web_app_dir => MOCK_WEB_APP_DIR
        }
      }
    })
    server.send(:deploy_web_apps)

    context_loaded = server.tomcat.host.find_children
    context_loaded.should have(3).web_apps

    expected = [ '/mock1', '/mock2', '/' ]
    context_loaded.each do |context|
      expected.delete(context.path).should == context.path
    end
  end

  it "loads the default application from the current directory if :web_apps is not present" do
    Trinidad.configure {|c| c.web_app_dir = MOCK_WEB_APP_DIR}
    server = deployed_server

    default_context_should_be_loaded(server.tomcat.host.find_children)
  end

  it "uses the default HttpConnector when http is not configured" do
    server = Trinidad::Server.new
    server.http_configured?.should be false

    server.tomcat.connector.protocol_handler_class_name.should == 'org.apache.coyote.http11.Http11Protocol'
  end

  it "uses the NioConnector when the http configuration sets nio to true" do
    server = configured_server({
      :web_app_dir => MOCK_WEB_APP_DIR,
      :http => {:nio => true}
    })
    server.http_configured?.should be true

    server.tomcat.connector.protocol_handler_class_name.should == 'org.apache.coyote.http11.Http11NioProtocol'
    server.tomcat.connector.protocol.should == 'org.apache.coyote.http11.Http11NioProtocol'
  end

  it "configures NioConnector with http option values" do
    server = configured_server({
      :web_app_dir => MOCK_WEB_APP_DIR,
      :http => {
        :nio => true,
        'maxKeepAliveRequests' => 4,
        'socket.bufferPool' => 1000
      }
    })

    connector = server.tomcat.connector
    connector.get_property('maxKeepAliveRequests').should == 4
    connector.get_property('socket.bufferPool').should == '1000'
  end

  it "configures the http connector address when the address in the configuration is not localhost" do
    server = configured_server({
      :web_app_dir => MOCK_WEB_APP_DIR,
      :address => '10.0.0.1'
    })

    connector = server.tomcat.connector
    connector.get_property("address").to_s.should == '/10.0.0.1'
  end

  it "adds the default lifecycle listener to each webapp" do
    Trinidad.configuration.web_app_dir = MOCK_WEB_APP_DIR
    server = deployed_server

    app_context = server.tomcat.host.find_child('/')

    app_context.find_lifecycle_listeners.map {|l| l.class.name }.
      should include('Trinidad::Lifecycle::WebApp::Default')
  end

  it "loads application extensions from the root of the configuration" do
    Trinidad.configure do |c|
      c.web_app_dir = MOCK_WEB_APP_DIR
      c.extensions = { :foo => {} }
    end
    server = deployed_server

    context = server.tomcat.host.find_child('/')
    context.doc_base.should == 'foo_web_app_extension'
  end

  it "doesn't create a default keystore when the option SSLCertificateFile is present in the ssl configuration options" do
    FileUtils.rm_rf 'ssl'

    server = configured_server({
      :ssl => {
        :port => 8443,
        :SSLCertificateFile => '/usr/local/ssl/server.crt'
      },
      :web_app_dir => MOCK_WEB_APP_DIR})

    File.exist?('ssl').should be false
  end

  it "uses localhost as host name by default" do
    configured_server.tomcat.host.name.should == 'localhost'
  end

  it "uses the option :address to set the host name" do
    server = configured_server :address => 'trinidad.host'
    server.tomcat.host.name.should == 'trinidad.host'
    server.tomcat.server.address.should == 'trinidad.host'
  end

  it "loads several applications if the option :apps_base is present" do
    begin
      FileUtils.mkdir 'apps_base'
      FileUtils.cp_r MOCK_WEB_APP_DIR, 'apps_base/test1'
      FileUtils.cp_r MOCK_WEB_APP_DIR, 'apps_base/test2'

      server = deployed_server :apps_base => 'apps_base'
      server.tomcat.host.find_children.should have(2).web_apps
    ensure
      FileUtils.rm_rf 'apps_base'
    end
  end

  it "loads rack apps from the apps_base directory" do
    begin
      FileUtils.mkdir 'apps_base'
      FileUtils.cp_r MOCK_WEB_APP_DIR, 'apps_base/test'

      server = deployed_server :apps_base => 'apps_base'
      listeners = find_listeners(server)
      listeners.first.webapp.should be_a(Trinidad::RackupWebApp)
    ensure
      FileUtils.rm_rf 'apps_base'
    end
  end

  it "adds the APR lifecycle listener to the server if the option is available" do
    server = configured_server( { :http => { :apr => true } } )

    server.tomcat.server.find_lifecycle_listeners.
      select {|listener| listener.instance_of?(Trinidad::Tomcat::AprLifecycleListener)}.
      should have(1).listener
  end

  it "adds the default lifecycle listener when the application is not packed with warbler" do
    server = deployed_server({
      :web_app_dir => MOCK_WEB_APP_DIR
    })
    listeners = find_listeners(server)
    listeners.should have(1).listener
  end

  it "adds the war lifecycle listener when the application is packed with warbler" do
    begin
      Dir.mkdir('apps_base')

      server = configured_server :apps_base => 'apps_base'
      server.send(:create_web_app, {
        :context_path => '/foo.war',
        :web_app_dir => 'foo.war'
      })
      listeners = find_listeners(server, Trinidad::Lifecycle::War)
      listeners.should have(1).listener
    ensure
      FileUtils.rm_rf 'apps_base'
    end
  end

  it "adds the APR lifecycle listener to the server if the option is available" do
    server = configured_server( { :http => { :apr => true } } )

    server.tomcat.server.find_lifecycle_listeners.
      select {|listener| listener.instance_of?(Trinidad::Tomcat::AprLifecycleListener)}.
      should have(1).listener
  end

  it "creates the host listener with all the applications into the server" do
    server = deployed_server({
      :web_apps => {
        :mock1 => {
          :web_app_dir => MOCK_WEB_APP_DIR
        },
        :mock2 => {
          :web_app_dir => MOCK_WEB_APP_DIR
        }
      }
    })

    host_listeners = server.tomcat.host.find_lifecycle_listeners.
      select {|listener| listener.instance_of?(Trinidad::Lifecycle::Host)}
    
    host_listeners.should have(1).listener
    listener = host_listeners[0]
    listener.app_holders.should have(2).applications
  end

  it "autoconfigures rack when config.ru is present in the app directory" do
    FakeFS do
      create_rackup_file('rack')
      server = deployed_server :web_app_dir => 'rack'

      server.tomcat.host.find_children.should have(1).application
    end
  end

  it "creates several hosts when they are set in configuration" do
    server = configured_server({ :hosts => {
      'foo' => 'localhost', :'lol' => 'lololhost'
    } })

    server.tomcat.engine.find_children.should have(2).hosts
  end

  it "adds aliases to the hosts when we provide an array of host names" do
    server = configured_server( :hosts => {
      'foo' => ['localhost', 'local'],
      'lol' => ['lololhost', 'lol']
    })

    hosts = server.tomcat.engine.find_children
    expect( hosts.map { |host| host.aliases }.flatten ).to eql ['lol', 'local']
  end

  it "doesn't add any alias when we only provide the host name" do
    server = configured_server( :hosts => {
      'foo' => 'localhost', 'lol' => 'lolhost'
    })

    hosts = server.tomcat.engine.find_children
    expect( hosts.map { |host| host.aliases }.flatten ).to eql []
  end

  it "sets default host app base to current working directory" do
    server = configured_server
    expect( server.tomcat.host.app_base ).to eql Dir.pwd
  end

  it "allows detailed host configuration" do
    server = configured_server( :hosts => {
      :default => {
        :name => 'localhost',
        :app_base => '/home/kares/apps',
        :unpackWARs => true,
        :deploy_on_startup => false,
      },
      :serverhost => {
        :aliases => [ :'server.host' ],
        :create_dirs => false
      }
    } )

    server.tomcat.engine.find_children.should have(2).hosts

    default_host = server.tomcat.host
    expect( default_host.name ).to eql 'localhost'
    expect( default_host.app_base ).to eql '/home/kares/apps'
    expect( default_host.unpackWARs ).to be true
    expect( default_host.deploy_on_startup ).to be false

    server_host = server.tomcat.engine.find_children.find { |host| host != default_host }
    expect( server_host.name ).to eql 'serverhost'
    expect( server_host.aliases[0] ).to eql 'server.host'
    expect( server_host.create_dirs ).to be false
  end

  it "selects apps for given host" do
    FileUtils.mkdir_p APP_STUBS_DIR + '/foo/mock1'
    FileUtils.mkdir_p APP_STUBS_DIR + '/foo/mock2'
    FileUtils.mkdir_p APP_STUBS_DIR + '/bar/main'
    FileUtils.mkdir_p APP_STUBS_DIR + '/baz/main'

    Dir.chdir(APP_STUBS_DIR) do
      server = deployed_server({
        :hosts => {
          '/var/domains/local' => [ 'localhost', 'local.host' ],
          :serverhost => {
            :app_base => '/var/domains/server',
            :aliases => [ 'server.host' ]
          }
        },
        :web_apps => {
          :foo1 => {
            :root_dir => 'foo/mock1', :hosts => ['localhost', 'local.host']
          },
          :foo2 => {
            :root_dir => 'foo/mock2', :host => 'localhost'
          },
          :bar => {
            :root_dir => 'bar/main', :hosts => [ 'server.host' ]
          },
          :baz => {
            :root_dir => 'baz/main', :host_name => 'serverhost'
          },
          :all => { :root_dir => 'all/app' }
        }
      })

      default_host = server.tomcat.host
      host_listener = default_host.find_lifecycle_listeners.
        find { |listener| listener.instance_of?(Trinidad::Lifecycle::Host) }

      app_dirs = host_listener.app_holders.map { |holder| holder.web_app.root_dir }
      expected = [ 'foo/mock1', 'foo/mock2', 'all/app' ].map { |dir| File.expand_path(dir) }
      expect( app_dirs ).to eql expected

      server_host = server.tomcat.engine.find_children.find { |host| host != default_host }
      host_listener = server_host.find_lifecycle_listeners.
        find { |listener| listener.instance_of?(Trinidad::Lifecycle::Host) }

      app_dirs = host_listener.app_holders.map { |holder| holder.web_app.root_dir }
      expected = [ 'bar/main', 'baz/main', 'all/app' ].map { |dir| File.expand_path(dir) }
      expect( app_dirs ).to eql expected
    end
  end

  it "creates several hosts when they are set in the web_apps configuration" do
    server = configured_server({
      :web_apps => {
        :mock1 => {
          :web_app_dir => 'foo/mock1', :hosts => 'localhost'
        },
        :mock2 => {
          :root_dir => 'bar/mock2', :host => 'lololhost'
        }
      }
    })

    children = server.tomcat.engine.find_children
    children.should have(2).hosts
  end

  it "doesn't create a host if it already exists" do
    server = configured_server({
      :web_apps => {
        :mock1 => {
          :root_dir => 'foo/mock1', :host => 'localhost'
        },
        :mock2 => {
          :web_app_dir => 'foo/mock2', :hosts => [ 'localhost' ]
        }
      }
    })

    children = server.tomcat.engine.find_children
    children.should have(1).hosts
  end

  it "sets up host base dir based on (configured) web apps" do
    FileUtils.mkdir_p APP_STUBS_DIR + '/foo/app'
    FileUtils.mkdir_p baz_dir = APP_STUBS_DIR + '/foo/baz'
    FileUtils.mkdir_p bar1_dir = APP_STUBS_DIR + '/var/www/bar1'
    FileUtils.mkdir_p APP_STUBS_DIR + '/var/www/bar2'

    server = configured_server({
      :web_apps => {
        :foo => {
          :root_dir => 'spec/stubs/foo/app', :host => 'localhost'
        },
        :baz => {
          :root_dir => baz_dir, :hosts => [ 'baz.host' ]
        },
        :bar1 => {
          :root_dir => bar1_dir, :host => 'bar.host'
        },
        :bar2 => {
          :root_dir => 'spec/stubs/var/www/bar2', :hosts => 'bar.host'
        }
      }
    })

    default_host = server.tomcat.host # localhost app_base is pwd by default
    expect( default_host.app_base ).to eql File.expand_path('.')

    baz_host = server.tomcat.engine.find_child('baz.host')
    expect( baz_host.app_base ).to eql File.expand_path(APP_STUBS_DIR + '/foo/baz')

    bar_host = server.tomcat.engine.find_child('bar.host')
    expect( bar_host.app_base ).to eql File.expand_path(APP_STUBS_DIR + '/var/www')
  end

  protected

  def configured_server(config = false)
    if config == false
      server = Trinidad::Server.new
    else
      server = Trinidad::Server.new(config)
    end
    server
  end

  def deployed_server(config = false)
    server = configured_server(config)
    server.send(:deploy_web_apps)
    server
  end

  private
  
  def find_listeners(server, listener_class = Trinidad::Lifecycle::Default)
    context = server.tomcat.host.find_children.first
    context.find_lifecycle_listeners.select do |listener|
      listener.instance_of? listener_class
    end
  end

  def default_context_should_be_loaded(children)
    children.should have(1).web_apps
    children[0].doc_base.should == MOCK_WEB_APP_DIR
    children[0].path.should == '/'
    children[0]
  end
  
end
