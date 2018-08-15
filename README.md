# FT8CallLogParse
Log parser for FT8Call that looks for special APRS messages and forwards to APRS.is

Requires Ruby and the following gems:
sudo gem install file-tail
sudo gem install maidenhead

Edit "station_call" to your station

Edit "ft8log" to where your FT8Call log is, e.g. "/home/pi/.local/share/FT8Call/ALL.TXT"

Run with "ruby aprs.rb"
