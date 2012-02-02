require 'rubygems'
require 'IRC'

class Irc
  attr_reader :channel
  attr_accessor :mc

  def initialize(server, port, channel)
    @mc = nil
    print "creating IRC object\n"
    @channel = channel
    @irc = IRC.new("minecraft-bridge", server, port, "minecraft chat bridging bot")
    IRCEvent.add_callback('endofmotd') { |event|
      print "joining channel...\n"
      @irc.join(channel)
    }
    IRCEvent.add_callback('join') { |event|
      #@irc.send_message(@channel, "hi, #{@channel}!")
    }
    IRCEvent.add_callback('privmsg') { |event|
      print "IRC: <#{event.from}> #{event.message}\n"
      if @mc != nil
        @mc.say "<#{event.from}> #{event.message}"
      end
    }
  end

  def say(msg)
    # oh gods, feedback loop
    if msg[0..4] == "<irc>"
      return
    end

    @irc.send_message(@channel, msg)
  end

  def run
    print "connecting...\n"
    @irc.connect
  end

  def close
    @irc.send_quit
  end
end

