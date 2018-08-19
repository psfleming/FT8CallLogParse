# aprs code taken from https://github.com/peteonrails/APRS-IS
require 'file/tail'
require 'socket'
require 'maidenhead'

# set your station callsign
STATIONCALL = "YOURCALL"
# make sure this is where your ALL.TXT is located
FT8LOG = "/home/pi/.local/share/FT8Call/ALL.TXT"

APRSSERVER = "rotate.aprs2.net"
VERSION = "0.1"

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

    # get decimal.minutes val. rjust to ensure 2 digits on left of .
    lat_dec = ( (("0.#{lat.split('.')[1]}".to_f) * 60).round(2) ).to_s.rjust(5, "0")
    lon_dec = ( (("0.#{lon.split('.')[1]}".to_f) * 60).round(2) ).to_s.rjust(5, "0")
    
    # get int val
    lat_int = lat.split('.')[0]
    lon_int = lon.split('.')[0].to_s.rjust(3, "0")

    return "#{lat_int}#{lat_dec}#{ns}/#{lon_int}#{lon_dec}#{ew}"

  end

  def report_loc(call, maiden, msg)
    latlon = Maidenhead.to_latlon(maiden).to_s().tr('[]','')
    lat = latlon.split(',')[0].strip
    lon = latlon.split(',')[1].strip
    formatted_loc = "=#{self.dec_toaprs(lat, lon)}-"
    self.packet(call, formatted_loc, msg)
  end

end
## end class

def send_aprsdata(rxbuff, key)
  puts "raw aprs string: #{rxbuff[key]}"
  call = rxbuff[key].split(':')[1].strip
  grid = rxbuff[key].split(':')[2].strip
  puts "call: #{call}"
  puts "grid: #{grid}"

  aprs = Aprs.new(APRSSERVER, 14580, STATIONCALL, VERSION)
  aprs.connect
  aprs.report_loc(call, grid, "FT8Call")

end

def get_freq_match(mlist, freq)
  mlist.each do |key, value|
    if (key - freq).abs < 15 then
      return key
    end
  end
  return nil
end

# check buffer for complete messages
# trim failed messages
def check_buffer(rxbuff, match)
  rxbuff.each do |key, value|

    # look for end of APRS message
    if value.include? ":RS"
      puts "End of APRS tag found: #{value}"
      # send aprs packet and clear buffer element
      begin
        send_aprsdata(rxbuff,match)
      rescue
        puts "error sending aprs packet: #{value}"
      end

      rxbuff.delete(key)
    end

    # trim failed messages
    if value.length > 50 then
      puts "trimmed #{key}, length was #{value.length}"
      rxbuff.delete(key)  
    end

  end
end

def getDataString(logline)
  datastring = []
  # get all txt right of ~, won't work if ~ in data string
  # example "222345   8  0.2  575 ~  rCwmrrZ+-ki7         1    AP:KI6SSI:"
  right_txt = logline.split('~')[1]
  right_txt.split().each_with_index do |val, index|
    if index > 1 then
      datastring << val
    end
  end
  return datastring.join(" ")
end

# tail file and look for APRS tags
rxbuff = Hash.new

File::Tail::Logfile.open(FT8LOG) do |log|
  log.backward(1).tail do |line|

    puts "new log line: #{line}"

    # if rx data line
    if line.split('~')[1] then
        rxfreq = line.split()[3].strip.to_i
        match = get_freq_match(rxbuff, rxfreq)
        datastr = getDataString(line)

        # if starts with AP:
        # add to buffer {rxfreq,message}
        if datastr.match(/^AP:/)
          puts "Start of APRS tag found"
          rxbuff.store(rxfreq, datastr)  

        # if there is already data for this freq in buffer
        elsif !match.nil?
          # keep appending if we are in the middle of APRS message
          rxbuff.store(match,rxbuff[match] + datastr)
        end

      check_buffer(rxbuff, match)
    end # end if data line

  end
end

