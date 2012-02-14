# encoding: utf-8
require 'socket'

class Mc
  attr_accessor :irc

  def initialize(server, port)
    @irc = nil
    @waitsend = []
    @server = server
    @port = port
  end

  def run
    print "dat minecraft server"
    @s = TCPSocket.new(@server, @port)

    # send first handshake packet (1.2w06a protocol)
    @s.send [0x02].pack("c") + mc_string("irc;localhost:25565"), 0 

    @got_handshake = false
    @logged_in = false

    while not @got_handshake
      nom @s
    end

    # got a handshake: time to log in!
    print "logging in..."
    @s.send mc_byte(0x01) + mc_int(25) + mc_string("irc") + mc_long(0) + mc_string("") + mc_int(0) + mc_byte(0) + mc_byte(0) + mc_ubyte(0) + mc_ubyte(0), 0

    while not @logged_in
      nom @s
    end

    print "logged in! main loop :)"

    while true
      nom @s
      if @waitsend.length > 0
        @s.send(@waitsend.pop, 0)
      end
    end
  end

  def say(msg)
    # sanitise
    # (note the following list has been butchered, because i did not need all the chars available
    #   and i couldn't be bothered to work out why ruby was choking on some of them)
    #print "starting sane part"
    sane = ' !"#$%&()*+,-./0123456789:;<=>£?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_abcdefghijklmnopqrstuvwxyz{|}~' + "'"
    safemsg = ""
    msg.each_char { |c|
      #print "dat comparison"
      #print "(testing #{c})"
      begin
        if sane.include?(c)
          #print "#{c} is sane; fine"
          safemsg << c
        else
          #print "not sane: using ?"
          safemsg << "?"
        end
      rescue
        #print "rescued; using ?"
        safemsg << "?"
      end
    }

    #print "yup, continuing..."

    # very very bad hack for making irc '/me's work
    matchdata = /\A<(.*?)> \?ACTION (.*)\?\Z/.match(safemsg)
    if matchdata != nil
      safemsg = "* #{matchdata[1]} #{matchdata[2]}"
    end

    if safemsg.length > 100
      safemsg = safemsg[0..96] + "..."
    end

    #print "\ni'mma pushing 0x03 + `#{safemsg}'\n"
    strong = mc_byte(0x03) + mc_string(safemsg)
    @waitsend.push(strong)
  end

  private
  def nom(socket)
    tb = socket.recv(1)
    t = identify_type(tb)
    
    if t == :Handshake
      recv_handshake(socket)
    elsif t == :KeepAlive
      recv_keepalive(socket)
    elsif t == :LoginRequest
      recv_login(socket)
    elsif t == :ChatMessage
      recv_chat(socket)
    elsif t == 0x04 # time update
      print "0x04, "
      socket.recv(8)
    elsif t == 0x06 # spawn position
      print "0x06, "
      socket.recv(12)
    elsif t == 0x08 # update health
      print "0x08, "
      socket.recv(8)
    elsif t == 0x0d # player position & look (!!!)
      print "0x0d, "
      socket.recv(41)
    elsif t == 0x0e # player digging
      print "0x0e, "
      socket.recv(11)
    elsif t == 0x0f # player block placement
      print "0x0f, "
      socket.recv(4) # x
      socket.recv(2) # y
      socket.recv(4) # z
      socket.recv(1) # direction
      skip_recv_slot(socket)
    elsif t == 0x10
      print "0x10, "
      socket.recv(2)
    elsif t == 0x11 # player using bed
      print "0x11, "
      socket.recv(14)
    elsif t == 0x12 # animation
      print "0x12, "
      socket.recv(5)
    elsif t == 0x14 # player spawned!
      print "0x14, "
      socket.recv(4) # id
      recv_mc_string(socket)
      socket.recv(4+4+4+1+1+2)
    elsif t == 0x05 # entity equipment
      print "0x05, "
      socket.recv(10)
    elsif t == 0x06 # spawn position
      print "0x06, "
      socket.recv(12)
    elsif t == 0x15 # item near or w/e
      print "0x15, "
      socket.recv(24)
    elsif t == 0x16 # collect item
      print "0x16, "
      socket.recv(8)
    elsif t == 0x17 # add object/vehicle
      print "0x17, "
      socket.recv(4) # eid
      socket.recv(1) # type
      socket.recv(12) # x, y, z
      fire_id = socket.recv(4).unpack("l>").first()
      if fire_id > 0
        socket.recv(6) # speed x, y, z
      end
    elsif t == 0x46 # new/invalid state
      print "0x46, "
      socket.recv(2)
    elsif t == 0x47 # thunderbolt
      print "0x47, "
      socket.recv(17)
    elsif t == 0x18 # mob spawn
      print "0x18, "
      recv_mob_spawn(socket)
    elsif t == 0x19 # entity: painting
      print "0x19, "
      socket.recv(4)
      recv_mc_string(socket)
      socket.recv(16)
    elsif t == 0x1a # experience orb
      print "0x1a, "
      socket.recv(18)
    elsif t == 0x1c # entity velocity
      print "0x1c, "
      socket.recv(10)
    elsif t == 0x1e # entity
      socket.recv(4)
    elsif t == 0x32 # pre-chunk
      print "0x32, "
      socket.recv(9)
    elsif t == 0x33 # map chunk
      print "0x33, "
      socket.recv(4) # block X coord
      socket.recv(2) # block Y coord
      socket.recv(4) # block Z coord
      socket.recv(1) # Size_X
      socket.recv(1) # Size_Y
      socket.recv(1) # Size_Z
      comp_size = socket.recv(4).unpack("l>").first
      socket.recv(comp_size)
    elsif t == 0xc9 # player list item
      recv_player_list_item(socket)
    elsif t == 0x64 # open window
      print "0x64, "
      socket.recv(2)
      recv_mc_string(socket)
      socket.recv(1)
    elsif t == 0x65 # close window
      print "0x65, "
      socket.recv(1)
    elsif t == 0x68 # window items
      print "0x68, "
      socket.recv(1) # window id
      num_slots = socket.recv(2).unpack("s>").first() # num. slots
      #print "(so parsing #{num_slots} slots), "
      while (num_slots > 0)
        skip_recv_slot(socket)
        num_slots = num_slots - 1
      end
    elsif t == 0x69 # update window property
      print "0x69, "
      socket.recv(5)
    elsif t == 0x6a # transaction
      print "0x6a, "
      socket.recv(4)
    elsif t == 0x82 # update sign
      print "0x82, "
      socket.recv(4 + 2 + 4)
      recv_mc_string(socket)
      recv_mc_string(socket)
      recv_mc_string(socket)
      recv_mc_string(socket)
    elsif t == 0x83 # item data
      print "0x83, "
      socket.recv(2 + 2)
      textlen = socket.recv(1).unpack("C").first()
      socket.recv(textlen)
    elsif t == 0x84 # update tile entity (12w06a)
      print "0x84, "
      socket.recv(10) # x, y, z
      socket.recv(1) # action
      socket.recv(12) # custom 1, custom 2, custom 3
    elsif t == 0x67 # set slot (not fully understood, apparently)
      socket.recv(1) # window id
      socket.recv(2) # slot id
      skip_recv_slot(socket)
    elsif t == 0x20 # entity look
      socket.recv(6)
    elsif t == 0x23 # entity head look
      socket.recv(5)
    elsif t == 0x1f # entity relative move
      socket.recv(7)
    elsif t == 0x22 # entity teleport
      socket.recv(18)
    elsif t == 0x21 # entity look & relative move
      socket.recv(9)
    elsif t == 0x36 # block action
      socket.recv(12)
    elsif t == 0x1d # destroy entity
      socket.recv(4)
    elsif t == 0x35 # block change
      socket.recv(11)
    elsif t == 0x28 # entity metadata
      socket.recv(4) # entity id
      skip_recv_metadata(socket)
    elsif t == 0x34 # multi-block change
      socket.recv(8) # chunk x, z
      array_size = socket.recv(2).unpack("s>").first()
      socket.recv(array_size * 2) # coordinate array of shorts
      socket.recv(array_size) # type array of bytes
      socket.recv(array_size) # metadata array of bytes
    elsif t == 0x26 # entity status
      socket.recv(5)
    elsif t == 0x29 # entity effect
      socket.recv(8)
    elsif t == 0x2a # remove entity effect
      socket.recv(5)
    elsif t == 0x2b # experience
      socket.recv(8)
    elsif t == 0x3c # explosion (!!!)
      socket.recv(24 + 4)
      record_count = socket.recv(4).unpack("l>").first()
      socket.recv(record_count * 3)
    elsif t == 0x3d # sound/particle effect
      socket.recv(17)
    elsif t == 0xc8 # increment statistic
      socket.recv(5)
    elsif t == 0xff # disconnect/kick
      throw "kicked: #{recv_mc_string(socket)}"
    else
      print "i dont know what (0x#{tb.getbyte(0).to_s(16)}) means, "
      throw tb.getbyte(0)
    end

  end

  def skip_recv_slot(socket)
    id = socket.recv(2).unpack("s>").first()
    
    if id != -1
      socket.recv(1) # item count
      socket.recv(2) # damage/block metadata
      enchantable_ids = [0x103,0x105,0x15a,0x167,0x10c,0x10d,0x10e,0x10f,0x122,0x110,0x111,0x112,0x113,0x123,0x10b,0x100,0x101,0x102,0x124,0x114,0x115,0x116,0x117,0x125,0x11b,0x11c,0x11d,0x11e,0x126,0x12a,0x12b,0x12c,0x12d,0x12e,0x12f,0x130,0x131,0x132,0x133,0x134,0x135,0x136,0x137,0x138,0x139,0x13a,0x13b,0x13c,0x13d]
      is_enchantable = enchantable_ids.include?(id)
      #print "\noh hey, slot item id #{id}.. enchantable: #{is_enchantable}, i think..\n"
      if is_enchantable
        nbt_data_len = socket.recv(2).unpack("s>").first()
        socket.recv(nbt_data_len)
      end
    end
  end

  def recv_player_list_item(socket)
    player_name = recv_mc_string(socket)
    online = parse_bool(socket.recv(1).unpack("C").first())
    #print "\nPlayer list item: #{player_name} is online? #{online}\n"
    ping = socket.recv(2)
  end

  def parse_bool(num)
    if num == 0
      return false
    elsif num == 1
      return true
    else
      throw "invalid bool parse result #{num}"
    end
  end

  def skip_recv_metadata(socket)
    #print "\nskip_recv_metadata starting.."
    while true do
      ub = socket.recv(1).unpack("C").first()
      if ub == 127
        #print "\nleaving skip_recv_metadata\n"
        break
      end

      # otherwise...
      #print "\nwhole byte: #{ub} id: #{ub & 0x1F} "
      dataType = ub >> 5
      #print "datatype: #{dataType}"
      if dataType == 0 # byte
        socket.recv(1)
      elsif dataType == 1 # short
        socket.recv(2)
      elsif dataType == 2 # int
        socket.recv(4)
      elsif dataType == 3 # float
        socket.recv(4)
      elsif dataType == 4 # string16
        recv_mc_string(socket)
      elsif dataType == 5
        socket.recv(2) # short
        socket.recv(1) # byte
        socket.recv(2) # short
      elsif dataType == 6
        socket.recv(4) # int
        socket.recv(4) # int
        socket.recv(4) # int
      end
    end
  end

  def recv_mob_spawn(socket)
    socket.recv(4) # entity id
    mob_type = socket.recv(1).unpack("c").first
    #print "\nmob type is #{mob_type}"
    socket.recv(12) # x, y, z ints
    socket.recv(1) # yaw
    socket.recv(1) # pitch
    socket.recv(1) # head yaw
    skip_recv_metadata(socket)
  end


  def mc_int(num)
    return [num].pack("l>")
  end
  
  def mc_short(num)
    return [num].pack("s>")
  end

  def mc_long(num)
    return [num].pack("q>")
  end

  def mc_byte(num)
    return [num].pack("c")
  end

  def mc_ubyte(num)
    return [num].pack("C")
  end

  def mc_string(strong)
    return [strong.length].pack("s>") + strong.encode(Encoding::UTF_16BE).force_encoding(Encoding::ASCII_8BIT)
  end

  def ircsay(msg)
    if @irc != nil
      @irc.say(msg)
    end
  end

  def recv_chat(socket)
    chat = recv_mc_string(socket)

    # strip color codes
    chatbits = chat.split('§')
    chat = chatbits[0]
    for i in 1..chatbits.length
      if chatbits[i] != nil
        chat << (chatbits[i])[1..(chatbits[i].length-1)]
      end
    end

    print chat

    # hacked mute support: DISABLED
    #if /\A<.*?> \./.match(chat) == nil
      # hack: ignore dave joining/leaving: DISABLED
      #if /\Ax124/.match(chat) == nil
        ircsay chat
      #end
    #end
  end

  def recv_mc_string(socket)
    count = socket.recv(2).unpack("s>").first()
    received_message = socket.recv(count*2)
    strongest = received_message.force_encoding(Encoding::UTF_16BE)

    return strongest.encode(Encoding::UTF_8)
  end

  def recv_handshake(socket)
    shake = recv_mc_string(socket)

    if shake.encode(Encoding::UTF_8) != "-"
      throw "can't continue; you need to turn off the server's online-mode. i can't handshake!"
    end

    print "got handshake response :)\n"
    @got_handshake = true
  end

  def recv_login(socket)
    print "got login; responding in kind"
    socket.recv(4) # entity id
    recv_mc_string(socket) # unused string
    socket.recv(8) # map seed
    recv_mc_string(socket) # level type
    socket.recv(4) # server mode
    socket.recv(1) # dimension
    socket.recv(1) # difficulty
    socket.recv(1) # world height
    socket.recv(1) # max players
    @logged_in = true
  end

  def recv_keepalive(socket)
    print "got keepalive; responding in kind"
    socket.send mc_byte(0) + socket.recv(4), 0
  end

  def identify_type(msgtype)
    msgtype = msgtype.getbyte(0)

    if msgtype == 0x00
      return :KeepAlive
    elsif msgtype == 0x01
      return :LoginRequest
    elsif msgtype == 0x02
      return :Handshake
    elsif msgtype == 0x03
      return :ChatMessage
    else
      return msgtype
    end
  end

end

