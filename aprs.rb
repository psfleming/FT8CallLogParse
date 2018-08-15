# aprs code taken from https://github.com/peteonrails/APRS-IS
require 'file/tail'
require 'socket'
require 'maidenhead'

ft8log = "/home/pi/.local/share/FT8Call/ALL.TXT"

## class
class Aprs
  def initialize(server, port, call, version)
    @server  = server
    @port    = port
    @call = call
    @version = version
  end
  
  def connect
    @socket = TCPSocket.open(@server, @port)
    @socket.puts "#{@server} #{@port}"
    pass = self.passcode(@call.upcase)
    @socket.puts "user #{@call.upcase} pass #{pass} ver \"#{@version}\""
  end
    
  def msg_filter()
    until @socket.eof? do
      msg = @socket.gets
      self.msg_dis(msg)
    end
  end
	
  def msg_raw()
    until @socket.eof? do
      msg = @socket.gets
      self.msg_dis_raw(msg)
    end
  end	
  
  def msg_dis(msg)
    Thread.new do
      msg.gsub!(/.*::/, "").gsub!(/\s*[:]/, ": ") #filters out data leaving only callsign and message
      puts "Debug(Incomming): #{msg}" if msg =~ /#{@call.upcase}/ 
    end
  end
   
  def msg_dis_raw(msg)
    Thread.new do
      puts "Debug(Incoming): #{msg}"
    end
  end

  def send_msg(msg, sendto)
    @socket.puts "#{@call.upcase}>APRS,TCPIP*,qAC,THIRD::#{sendto.upcase}   :#{msg}" #3 spaces between call and msg
  end
  
  def packet(call = @call, position, comment)
    init = "#{call.upcase}>APRS,TCPIP*:"
    send = "#{init}#{position} #{comment}"
    puts "Debug(Outgoing): #{send}"
    @socket.puts "#{send}"
  end

  def passcode(call_sign) ## credit to https://github.com/xles/aprs-passcode/blob/master/aprs_passcode.rb
	call_sign.upcase!
	call_sign.slice!(0,call_sign.index('-')) if call_sign =~ /-/
	hash = 0x73e2
	flag = true
	call_sign.split('').each{|c|
	hash = if flag
	(hash ^ (c.ord << 8))
		else
		(hash ^ c.ord)
		end
	flag = !flag
	}
	hash & 0x7fff
   end
  
  # decimal lat lon to aprs format
  # dec_toaprs("38.653646", "-121.080208")
  # 3839.22N/12104.81W
  # final msg format should be aprs.packet("=3839.22N/12104.81W-", "FT8Call")
  def dec_toaprs(lat, lon)
    # get NS EW and trim -
    ns = "N"
    if lat.index("-") == 0 then
      lat.tr!('-', '')
      ns = "S"
    end
    ew = "E"
    if lon.index("-") == 0 then
      lon.tr!('-', '')
      ew = "W"
    end

    # get decimal.minutes val
    lat_dec = (("0.#{lat.split('.')[1]}".to_f) * 60).round(2)
    # rjust to ensure 2 digits on left of .
    lon_dec = ( (("0.#{lon.split('.')[1]}".to_f) * 60).round(2) ).to_s.rjust(5, "0")
    
    # get int val
    lat_int = lat.split('.')[0]
    lon_int = lon.split('.')[0]

    return "#{lat_int}#{lat_dec}#{ns}/#{lon_int}#{lon_dec}#{ew}"

  end

  def report_loc(call, maiden, msg)
    latlon = Maidenhead.to_latlon(maiden).to_s().tr('[]','')
#    puts latlon
    lat = latlon.split(',')[0].strip
    lon = latlon.split(',')[1].strip
    formatted_loc = "=#{self.dec_toaprs(lat, lon)}-"
#    puts "self.packet(#{formatted_loc}, #{msg})"
    self.packet(formatted_loc, msg)
  end

end
## end class

def send_aprsdata(shash, key)
  puts "raw aprs string: #{shash[key]}"
  call = shash[key].split(':')[1].strip
  grid = shash[key].split(':')[2].strip
  puts "call: #{call}"
  puts "grid: #{grid}"

  aprs = Aprs.new("rotate.aprs2.net", 14580, "KI6SSI", "0.1")
  aprs.connect
  aprs.report_loc(call, grid, "FT8Call")

  # clear hash element
  shash.delete(key)
end

def get_freq_match(mlist, freq)
  mlist.each do |key, value|
    if (key - freq).abs < 15 then
      return key
    end
  end
  return nil
end

# trim failed aprs messages
def trim_failed(mlist)
  mlist.each do |key, value|
    if value.length > 50 then
      puts "trimmed #{key}, length was #{value.length}"
      mlist.delete(key)  
    end
  end
end

# tail file and look for APRS tags
rxbuff = Hash.new

File::Tail::Logfile.open(ft8log) do |log|
  log.backward(1).tail do |line|

    puts "new log line: #{line}"

    # if rx data line
    if line.split('~')[1] then
        rxfreq = line.split()[3].strip.to_i
        match = get_freq_match(rxbuff, rxfreq)

        # if starts with AP:
        # add to buffer {rxfreq,message}
        if line.split('~')[1].strip.match(/^AP:/)
          puts "Start of APRS tag found"
          rxbuff.store(rxfreq, line.split('~')[1].strip)  

        # if there is already data for this freq in buffer
        elsif !match.nil?
          # puts match
          # look for end of APRS message
          if line.split('~')[1].strip.include? ":RS"
            puts "End of APRS tag found"
            rxbuff.store(match,rxbuff[match] + line.split('~')[1].strip)
            # send aprs packet and clear buffer element
            send_aprsdata(rxbuff,match)
          else
            # keep appending if we are in the middle of APRS message
            rxbuff.store(match,rxbuff[match] + line.split('~')[1].strip)
          end

        end

      trim_failed(rxbuff)
    end # end if data line

  end
end


## 
#latlon = Maidenhead.to_latlon("CM98lp06jv").to_s().tr('[]','')
#lat = latlon.split(',')[0].strip
#lon = latlon.split(',')[1].strip
#puts Aprs.dec_toaprs(lat, lon)
#aprs = Aprs.new("rotate.aprs2.net", 14580, "KI6SSI", "0.1")
#aprs.connect #connects to aprs network
#aprs.report_loc("KI6SSI", "CM98lp06iv", "FT8Call")
#  aprs.packet("=3839.22N/12104.81W-", "FT8Call")
#puts aprs.passcode("ki6ssi")
