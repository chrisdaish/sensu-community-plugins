#!/usr/bin/env ruby
#
# Check Supervisor, via it's UNIX domain socket, see unix_http_server section in http://supervisord.org/configuration.html
# ===
#
# Check all supervisor processes are running, via it's UNIX domain socket
#
#   Author: Mathias Bogaert
#   Copyright (c) 2014 Buttercoin
#
# PLATFORMS:
#   all
#
# DEPENDENCIES:
#   gem: libxml-xmlrpc
#   gem: sensu-plugin
#
# Released under the same terms as Sensu (the MIT license); see LICENSE
# for details.

require 'rubygems' if RUBY_VERSION < "1.9"
require 'sensu-plugin/check/cli'

require "net/http"
require "socket"
require "xml/libxml/xmlrpc"

class CheckSupervisorSocket < Sensu::Plugin::Check::CLI

  option :socket,
    :description  => 'Supervisor UNIX domain socket',
    :short        => '-s SOCKET',
    :long         => '--socket SOCKET',
    :default      => '/var/run/supervisor.sock'

  option :username,
    :description  => 'Supervisor UNIX domain socket username',
    :short        => '-u USERNAME',
    :long         => '--username USERNAME'

  option :password,
    :description  => 'Supervisor UNIX domain socket password',
    :short        => '-p PASSWORD',
    :long         => '--password PASSWORD'

  option :critical,
    :description  => 'Supervisor states to consider critical',
    :short        => '-c STATE[,STATE...]',
    :long         => '--critical STATE[,STATE...]',
    :proc         => Proc.new { |v| v.upcase.split(",") },
    :default      => ['FATAL']

  option :help,
    :description  => 'Show this message',
    :short        => '-h',
    :long         => '--help'

  def run

    if config[:help]
      puts opt_parser
      exit
    end

    begin
      @super = Net::BufferedIO.new(UNIXSocket.new(config[:socket]))
    rescue
      critical "Tried to access UNIX domain socket #{config[:socket]} but failed"
    end

    begin
      request = Net::HTTP::Post.new("/RPC2")
      request.content_type = "text/xml"
      request.basic_auth config[:username], config[:password] if config[:username]
      request.body = XML::XMLRPC::Builder.call("supervisor.getAllProcessInfo")
      request.exec(@super, "1.1", "/RPC2")

      # wait for and parse the http response
      loop do
        response = Net::HTTPResponse.read_new(@super)
        break unless response.kind_of?(Net::HTTPContinue)
      end

      response.reading_body(@super, request.response_body_permitted?) { }
    rescue
      critical "Tried requesting XMLRPC 'supervisor.getAllProcessInfo' from UNIX domain socket #{config[:socket]} but failed"
    end

    XML::XMLRPC::Parser.new(response.body).params do |process|
      critical "#{process["name"]} not running: #{process["statename"].downcase}" if config[:critical].include?(process["statename"])
    end

    ok "All processes running"

  end

end
