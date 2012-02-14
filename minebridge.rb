require './mc.rb'
require './irc2.rb'

mc = Mc.new("localhost", 25565)
irc = Irc.new("irc.freenode.net", 6667, "##calpol")

ircThread = Thread.new { irc.run }
print "gonna sleep"
print "i slept #{sleep 5}"
mcThread = Thread.new { mc.run }
print "i slept #{sleep 5}"

irc.mc=(mc)
mc.irc=(irc)

print "up!"
mcThread.join
throw "mc connection died"
ircThread.join
