require 'socket'
require 'io/wait'

class Irc
  attr_reader :channel
  attr_accessor :mc

  def initialize(server, port, channel)
    @mc = nil
    @channel = channel
    @waitsend = []
    @server = server
    @port = port
    
    #IRCEvent.add_callback('privmsg') { |event|
    #  print "IRC: <#{event.from}> #{event.message}\n"
    #  if @mc != nil
    #    @mc.say "<#{event.from}> #{event.message}"
    #  end
    #}
  end

  # note: not safe if msg contains \n
  def say(msg)
    # oh gods, feedback loop
    if msg[0..4] == "<irc>"
      return
    end

    #@irc.send_message(@channel, msg)
    @waitsend.push("PRIVMSG #{@channel} :#{msg}\n")
  end

  def run
    print "connecting...\n"
    @s = TCPSocket.new(@server, @port)
    @waitsend.push "PASS 0\nNICK mc-bridge2\nUSER mcirc nope yope :Minecraft<->IRC chat bridge\nJOIN #{@channel}\n"

    wst = Thread.new { sendThread }

    while line = @s.gets
      print line + "\n"

      line.gsub! /[\n|\r]/, ''

      pingMatchData = /\APING (.*)\Z/.match(line)
      
      if pingMatchData != nil
        @waitsend.push "PONG #{pingMatchData[1]}\n"
      end

      pmMatchData = /\A:(.*?)!.*?@.*? PRIVMSG #{channel} :(.*)\Z/.match(line) 

      if pmMatchData != nil
        if @mc != nil
          @mc.say "<#{pmMatchData[1]}> #{pmMatchData[2]}"
        else
          print "GOT:: <#{pmMatchData[1]}> #{pmMatchData[2]}\n"
        end
      end
    end

    wst.join

  end

  def close
    @s.close
    @s = nil
  end

  private
  def sendThread
    while @s != nil
      if @waitsend.length > 0
        strong = @waitsend.pop
        @s.send strong, 0
      else
        sleep 0.1
      end
    end
  end
end

#irc2wat = Irc.new("irc.freenode.net", 6667, "##timehive")
#irc2wat.run

