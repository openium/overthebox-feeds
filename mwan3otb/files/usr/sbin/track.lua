#! /usr/bin/env lua

local p   = require 'posix'
local sig = require "posix.signal"

local json	= require("luci.json")
local uci	= require("luci.model.uci").cursor()
local sys	= require("luci.sys")

-- sig.signal (sig.SIGQUIT, handle_exit)
-- sig.signal (sig.SIGTERM, handle_exit)
-- sig.signal (sig.SIGINT,  handle_exit)

local function handle_exit()
	p.closelog()
	os.exit();
end

function ping ( host, interface, timeout)
	if p.SOCK_RAW and p.SO_BINDTODEVICE then
		-- Open raw socket
		local fd, err = p.socket(p.AF_INET, p.SOCK_RAW, p.IPPROTO_ICMP)
		if not fd then return fd, err end

		-- timeout on socket
		local ok, err = p.setsockopt(fd, p.SOL_SOCKET, p.SO_RCVTIMEO, 1, timeout )
		if not ok then return ok, err end

		-- bind to specific device
		local ok, err = p.setsockopt(fd, p.SOL_SOCKET, p.SO_BINDTODEVICE, interface)
		if not ok then return ok, err end

		-- Create raw ICMP echo (ping) message
		-- https://fr.wikipedia.org/wiki/Internet_Control_Message_Protocol
		local data = string.char(0x08, 0x00, 0x7a, 0xa7, 0x6e, 0x63, 0x00, 0x04, 0x0F, 0xF0, 0xFF)

		local t1 = p.clock_gettime(p.CLOCK_REALTIME)
		-- Send message
		local ok, err = p.sendto(fd, data, { family = p.AF_INET, addr = host, port = 0 })
		if not ok then return ok, err end

		-- Read reply
		local data, sa = p.recvfrom(fd, 1024)
		local t2 = p.clock_gettime(p.CLOCK_REALTIME) 
		if fd then p.close(fd) end
		if data then
			local r = string.byte(data, 21, 22) -- byte of the first char
			if     r == 0 then return true, (diff_nsec(t1, t2)/1000000)
			elseif r==3   then return false, "network error"
			elseif r==11  then return false, "timeout error"
			else
				-- hex_dump(data)
                                return false, "other error : "..r
			end
		else
			return false, sa
		end	
		return data, sa
	end
	return false, "not raw socket"
end

function dns_request( host, interface, timeout, name)
	local fd, err = p.socket(p.AF_INET, p.SOCK_DGRAM, 0)
	if not fd then return fd, err end

	p.bind (fd, { family = p.AF_INET, addr = "0.0.0.0", port = 0 })

	-- timeout on socket
	local ok, err = p.setsockopt(fd, p.SOL_SOCKET, p.SO_RCVTIMEO, 1, timeout )
	if not ok then return ok, err end

	-- bind to specific device
	local ok, err = p.setsockopt(fd, p.SOL_SOCKET, p.SO_BINDTODEVICE, interface)
	if not ok then return ok, err end

	local domain = "www.google.com"
	math.randomseed( os.time() )

	domain = string.gsub(domain, '%.', string.char(0x03))
	local data = string.char( math.random(255), math.random(255), 0x01, 0x20, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x03) .. domain .. string.char(0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x29, 0x10, 0x00, 0x00,   0x00, 0x00, 0x00, 0x00, 0x00)

	local t1 = p.clock_gettime(p.CLOCK_REALTIME)
        -- Send message
	local ok, err = p.sendto (fd, data, { family = p.AF_INET, addr = host, port = 53 })
	if not ok then return ok, err end

	local data, sa = p.recvfrom(fd, 1024)
	local t2 = p.clock_gettime(p.CLOCK_REALTIME)
	if fd then p.close(fd) end
	if data then
		local r = string.byte(data, 3, 4) -- byte of the first char
		if     r == 129 then return true, (diff_nsec(t1, t2)/1000000)
		else
			-- hex_dump(data)
			return false, "other error : "..r
		end
	else
		return false, sa
	end
end



function socks_request( host, interface, timeout, port )
	local fd, err = p.socket(p.AF_INET, p.SOCK_STREAM, 0)
	if not fd then return fd, err end

	p.bind (fd, { family = p.AF_INET, addr = "0.0.0.0", port = 0 })

	-- timeout on socket
	local ok, err = p.setsockopt(fd, p.SOL_SOCKET, p.SO_RCVTIMEO, 1, timeout )
	if not ok then return ok, err end
	local ok, err = p.setsockopt(fd, p.SOL_SOCKET, p.SO_SNDTIMEO, 1, timeout )
	if not ok then return ok, err end

	-- bind to specific device
	local ok, err = p.setsockopt(fd, p.SOL_SOCKET, p.SO_BINDTODEVICE, interface)
	if not ok then return ok, err end

	local r, err = p.getaddrinfo (host, port, { family = p.AF_INET, socktype = p.SOCK_STREAM })
	if not r then return false, err end

	local t1 = p.clock_gettime(p.CLOCK_REALTIME)

	local ok, err, e = p.connect (fd, r[1] )

	local t2 = p.clock_gettime(p.CLOCK_REALTIME)

--	local sa = p.getsockname(fd)
--	print("Local socket bound to " .. sa.addr .. ":" .. tostring(sa.port))
	if fd then p.close(fd) end

	if err then return false, err end

	return true, (diff_nsec(t1, t2)/1000000)
end




function diff_nsec(t1, t2)
	local ret = ( t2.tv_sec * 1000000000 + t2.tv_nsec) - (t1.tv_sec * 1000000000 + t1.tv_nsec)
	if ret < 0 then
		print("euhh :", t2.tv_sec, t1.tv_sec, t2.tv_nsec, t1.tv_nsec)
		print(( t2.tv_sec * 1000000000 + t2.tv_nsec), (t1.tv_sec * 1000000000 + t1.tv_nsec))
		print(ret)
		os.exit(-1)
	end
	return ret
end

function log(str)
	p.syslog( p.LOG_NOTICE, opts["i"] .. '.' .. str)
end
function debug(str)
        p.syslog( p.LOG_DEBUG, opts["i"] .. '.' .. str)
end

function hex_dump(buf)
      for byte=1, #buf, 16 do
         local chunk = buf:sub(byte, byte+15)
         io.write(string.format('%08X  ',byte-1))
         chunk:gsub('.', function (c) io.write(string.format('%02X ',string.byte(c))) end)
         io.write(string.rep(' ',3*(16-#chunk)))
         io.write(' ',chunk:gsub('%c','.'),"\n") 
      end
   end


local arguments = {
	{"help",        "none",     'h', "bool",   "this help message" },
	{"device",      "required", 'd', "string", "device to check" },
	{"interface",   "required", 'i', "string", "network interface to check"},
	{"method", 	"optional", 'm', "string", "method to check : icmp (default), dns, socks"},
	{"reliability", "required", 'r', "number", "how many success we have to consider the interface up"},
	{"count",       "required", 'c', "number", "count number of test we make"},
	{"timeout",     "required", 't', "number", "request timeout"},
	{"interval",    "required", 'v', "number", "interval between 2 requests"},
	{"down",        "required", 'o', "number", "how many test we failed before consider it's down"},
	{"up",          "required", 'u', "number", "how many test we succeed before consider it's up"}
}

function arguments:usage()
	print("Usage : track.lua arguments host")
	print("Arguments:")
	for k, v in pairs(arguments) do
                if type(v) == "table" then
			print(string.format("  -%s or --%-20s %-6s %s", v[3], v[1], v[4], v[5]))
		end
	end
	os.exit()
end

function arguments:short() 
	local s = ""
	for k, v in pairs(arguments) do
		if type(v) == "table" then
			if v[4] == "bool" then
				s = s .. v[3]
			else
				s = s .. v[3] .. ':'
			end
		end
	end
	return s
end

function arguments:long()
        local s = {}
        for k, v in pairs(arguments) do
                if type(v) == "table" then
			table.insert(s, {v[1], v[2], v[3] })
                end
        end
        return s
end

function arguments:all_required_are_not_here(opt)
	for k, v in pairs(arguments) do
                if type(v) == "table" then
			if v[2] == "required" and  opt[ v[3] ] == nil then
				return false, v[1].." is missing"
			end
                end
        end
        return true
end

p.openlog("track")

opts={}
local last_index = 1
for r, optarg, optind, li in p.getopt (arg, arguments:short(), arguments:long()) do
  if r == '?' then return print  'unrecognized option' end
  last_index = optind
  opts[ r ] = optarg or true
end

servers={}
for i = last_index, #arg do
	if string.find(arg[i], "%d+.%d+.%d+.%d+") then
--		print("track : "..arg[i])
		table.insert(servers, arg[i])
	else
		print("not reconize : "..arg[i])
	end
end

if opts["h"] then
	arguments:usage()
end

local ok, err = arguments:all_required_are_not_here(opts) 
if not ok then
        arguments:usage()
end

if table.getn(servers) == 0 then
	print("no server found")
        arguments:usage()
end



local method
if opts["m"] == "dns" then
	debug("test dns method")
	method = function(s) return dns_request( s, opts["i"], opts["t"], "www.google.fr") end
elseif opts["m"] == "sock" then
	debug("test sock method")
	method = function(s) return socks_request(s, opts["i"], opts["t"], "1090") end
else
	debug("test icmp method")
	method = function(s) return ping(s , opts["i"], opts["t"]) end
end

local fn = "/var/run/mwan3track-"..opts["i"]..".pid"
local fd, err = io.open(fn, 'r')
if fd then
	io.input(fd)
	local pid = io.read()
	io.close(fd)
	if pid and tonumber(pid) > 1 then p.kill(pid, sig.SIGTERM) end
end

local fd, err = io.open(fn, 'w')
io.output(fd)
io.write(p.getpid(), "\n")
io.close(fd)

local nb_up = tonumber(opts["u"])
local nb_down = tonumber(opts["o"])

local score=nb_up + nb_down
local init_score = score
local host_up_count=0
local lost=0

function run(command)
	debug("execute : " .. command)
	os.execute(command)
--	local handle = io.popen(command)
--	local result = handle:read("*a")
--	handle:close()
end

-- Circular buffer for ping stats collection
local pingstats 	= {}
pingstats.numvalue 	= 60
pingstats.entries	= 0
pingstats.pos		= 0

function pingstats:push(value)
	pingstats[pingstats.pos] = value
	pingstats.pos = pingstats.pos + 1
	-- 
	if pingstats.pos < pingstats.numvalue then
		pingstats.entries = pingstats.entries + 1
	else
		pingstats.pos = pingstats.pos - pingstats.numvalue
	end
end

function pingstats:avg()
	sum = 0
	if pingstats.entries == 0 then
		return sum
	end
	for index = #pingstats, 1, -1 do
		local item = pingstats[index]
		sum = sum + item
	end
	return sum / #pingstats
end

function pingstats:min()
	min = 10000
        if pingstats.entries == 0 then
                return min
        end
        for index = #pingstats, 1, -1 do
		min = math.min(pingstats[index], min)
        end
        return min
end

function pingstats:getn(index)
	index = math.abs(index)

	if index >= pingstats.numvalue then 
		return 0
	end

	local pos = pingstats.pos - 1 - index
	if pos < 1 then 
		pos = pingstats.numvalue + pos
	end

        return pingstats[pos] or 10000
end

function pingstats:setn(index, value)
        index = math.abs(index)

        if index >= pingstats.numvalue then
                return 0
        end

        local pos = pingstats.pos - 1 - index
        if pos < 1 then
                pos = pingstats.numvalue + pos
        end
	pingstats[pos] = value
end

-- Bandwith stats
local bw_stats	= {}
bw_stats.values = {}
bw_stats.command= "/usr/bin/luci-bwc"
function bw_stats:collect()
	-- run bandwidth monitor
	local handle = io.popen(string.format("%s -i %s", bw_stats.command, opts["i"]))
	local result = handle:read("*a")
	handle:close()
	-- store rsult in table
	bw_stats.values = json.decode("[" .. string.gsub(result, '[\r\n]', '') .. "]")
	return bw_stats.values
end

function bw_stats:avgdownload(timestamp)
        local sum=0
	local count=0

	local mintimestamp
	local maxtimestamp
	local minvalue
	local maxvalue

        for index = #bw_stats.values, 1, -1 do
		if bw_stats.values[index][1] >= timestamp then
			if mintimestamp == nil then
				mintimestamp = bw_stats.values[index][1]
			end
			if maxtimestamp == nil then
				maxtimestamp = bw_stats.values[index][1]
			end
			mintimestamp = math.min(mintimestamp, bw_stats.values[index][1])
			maxtimestamp = math.max(maxtimestamp, bw_stats.values[index][1])
			if minvalue == nil then
				minvalue = bw_stats.values[index][2]
			end
			if maxvalue == nil then
				maxvalue = bw_stats.values[index][2]
			end
			minvalue = math.min(minvalue, bw_stats.values[index][2])
			maxvalue = math.max(maxvalue, bw_stats.values[index][2])

			sum = sum + bw_stats.values[index][2]
			count = count + 1
		end
        end
	if count > 0 then
		local value = math.floor((((maxvalue - minvalue) / (maxtimestamp - mintimestamp)) * 8) / 1024)
		bw_stats.maxdownloadvalue = math.max(bw_stats.maxdownloadvalue, value)
	        return value
	else
		return nil
	end
end

function bw_stats:avgupload(timestamp)
    local sum=0
    local count=0

    local mintimestamp
    local maxtimestamp
    local minvalue
    local maxvalue

        for index = #bw_stats.values, 1, -1 do
        if bw_stats.values[index][1] >= timestamp then
            if mintimestamp == nil then
                mintimestamp = bw_stats.values[index][1]
            end
            if maxtimestamp == nil then
                maxtimestamp = bw_stats.values[index][1]
            end
            mintimestamp = math.min(mintimestamp, bw_stats.values[index][1])
            maxtimestamp = math.max(maxtimestamp, bw_stats.values[index][1])
            if minvalue == nil then
                minvalue = bw_stats.values[index][4]
            end
            if maxvalue == nil then
                maxvalue = bw_stats.values[index][4]
            end
            minvalue = math.min(minvalue, bw_stats.values[index][4])
            maxvalue = math.max(maxvalue, bw_stats.values[index][4])

            sum = sum + bw_stats.values[index][4]
            count = count + 1
        end
        end
    if count > 0 then
    		local value = math.floor((((maxvalue - minvalue) / (maxtimestamp - mintimestamp)) * 8) / 1024)
		bw_stats.maxuploadvalue = math.max(bw_stats.maxuploadvalue, value)
		return value
    else
        return nil
    end
end

bw_stats.maxdownloadvalue = 512
function bw_stats:maxdownload()
	return bw_stats.maxdownloadvalue
end

bw_stats.maxuploadvalue = 128
function bw_stats:maxupload()
	return bw_stats.maxuploadvalue
end

-- used by conntrack bw stats
local ipsrc     = uci:get("network", opts["i"], "ipaddr")
local dports    = { uci:get("shadowsocks","proxy","port"), uci:get("vtund","tunnel","port") }
function bw_stats:conntrack(ipsrc, dports)
        local counter=0
        for _, stats in pairs(sys.net.conntrack())
        do
                if stats["layer4"] == "tcp" and stats["src"] == ipsrc then
                        if dports[ stats["dport"] ] then
                            counter = counter + stats["bytes"]
                        end
                end
        end
        return math.floor((counter * 8)/ 1024)
end

-- Shaping helper object
local shaper  = {}
shaper.interface = opts["i"]
shaper.mode = uci:get("network", opts["i"], "autoshape") or "off" -- auto, static
shaper.mindownload = tonumber(uci:get("network", opts["i"], "mindownload")) or 512 -- kbit/s
shaper.minupload = tonumber(uci:get("network", opts["i"], "minupload")) or 128 -- kbit/s
shaper.qostimeout = tonumber(uci:get("network", opts["i"], "qostimeout")) or 30 -- min
shaper.pingdelta = tonumber(uci:get("network", opts["i"], "pingdelta")) or 100 -- ms
shaper.bandwidthdelta = tonumber(uci:get("network", opts["i"], "bandwidthdelta")) or 100 -- kbit/s
shaper.ratefactor = tonumber(uci:get("network", opts["i"], "ratefactor")) or 1 -- 0.9 mean 90%
-- Shaper timers
shaper.congestedtimestamp = nil
shaper.qostimestamp = nil
shaper.losttimestamp = nil

-- Shaper functions
function shaper:pushPing(lat)
	if lat == false then
		lat = 1000
		bw_stats:collect()
	end
	pingstats:push(lat)

	if shaper.mode ~= "off" and (lat > (pingstats:min() + shaper.pingdelta)) then
		if shaper.congestedtimestamp == nil then
			log("Starting bandwidth stats collector on " .. opts["i"])
			shaper.congestedtimestamp = os.time()
		end
	        bw_stats:collect()
	end
end

function shaper:isCongested()
	if pingstats:getn(0) > (min + shaper.pingdelta) and pingstats:getn(-1) > (min + shaper.pingdelta) and pingstats:getn(-2) > (min + shaper.pingdelta) then
		return true
	else
		return false
	end
end

function shaper:update()
        if shaper.mode == "auto" then
		if shaper.qostimestamp and shaper.qostimeout and (os.time() > (shaper.qostimestamp + shaper.qostimeout * 60)) then
			log(string.format("disabling download QoS after %s min", shaper.qostimeout))
			shaper:disableQos()
		end
		if shaper:isCongested() then
			local download = bw_stats:avgdownload(shaper.congestedtimestamp - 2)
			local upload   = bw_stats:avgupload(shaper.congestedtimestamp - 2)
			log("avg rate since ".. shaper.congestedtimestamp .." is " .. download .. " kbit/s down and " .. upload .." kbit/s up")
			-- upload congestion detected
			if upload > download then
				shaper.upload = math.floor(upload * shaper.ratefactor)
				if shaper.download ~= nil then
					shaper:enableQos()
				end
			else
				shaper.download = math.floor(download * shaper.ratefactor)
				shaper:enableQos()
			end
		end
	elseif shaper.mode == "static" then
		if shaper.qostimestamp == nil then
			shaper.upload = tonumber(uci:get("network", shaper.interface, "upload"))
			shaper.download = tonumber(uci:get("network", shaper.interface, "download"))
			shaper:enableQos()
		end
	end
end

function shaper:enableQos()
	local download = shaper.download
	local upload = shaper.upload
	-- Check download speed
	if download == nil then
		log("no download speed setted")
		return false
	end
	-- If no upload set use download speed
	if upload == nil then
		upload = download
	end
	--
	if shaper.qostimestamp and ((os.time() - shaper.qostimestamp) < 60) then
		log("Link still congested reducing rate of 5%")
		download	= math.floor(download * 0.95)
		upload		= math.floor(upload * 0.95)
	end
	-- Check minimal speeds
	if (download < shaper.mindownload) or (upload < shaper.minupload) then
		log("minimal speeds are not reached")
	end
	-- Min speeds are reach applying QoS
	log("Setting QoS download to " .. download .. " kbit/s and upload to " .. upload .. " kbit/s")
	uci:set("qos", shaper.interface, "interface")
	uci:set("qos", shaper.interface, "classgroup", 'Default')
	uci:delete("qos", shaper.interface, "halfduplex")
	uci:set("qos", shaper.interface, "overhead", '1')
	uci:set("qos", shaper.interface, "download", download)
	uci:set("qos", shaper.interface, "upload", upload)
	uci:set("qos", shaper.interface, "enabled", '1')
	uci:commit("qos")
	-- reloading QoS
	run(string.format("/etc/init.d/qos enabled && /usr/lib/qos/generate.sh interface %s | sh", shaper.interface))
	if shaper.qostimestamp == nil then
		run("/etc/init.d/qos reload")
	end
	shaper.qostimestamp = os.time()
end

function shaper:disableQos()
	log(string.format("Disabling QoS on interface %s", shaper.interface))
	-- updating uci
	uci:delete("qos", shaper.interface, "download")
	uci:delete("qos", shaper.interface, "upload")
	uci:set("qos", shaper.interface, "enabled", '0')
	uci:commit("qos")
	-- restarting qos
	run(string.format("/etc/init.d/qos enabled && /usr/lib/qos/generate.sh interface %s | sh", shaper.interface))
	run("/etc/init.d/qos reload")
	shaper.qostimestamp=nil
	shaper.congestedtimestamp=nil
end

-- Enable shaper only on multipath interface
if uci:get("network", opts["i"], "multipath") == "on" then
	shaper.mode = uci:get("network", opts["i"], "autoshape")
end

shaper:disableQos()
while true do

	for i = 1, #servers do
		local ok, msg = method( servers[i] )
		if ok then
			host_up_count = host_up_count + 1

			lat = tonumber(msg)
			shaper:pushPing(lat)
			local min = pingstats:min()
			log("check: "..servers[i].. " OK " .. lat .. "ms" .. " was " .. pingstats:getn(-1) .. " " .. pingstats:getn(-2) .. " " .. pingstats:getn(-3) .. " (" .. tostring(min) .. " min)")
		else
			lost = lost + 1

			shaper:pushPing(false)
			log("check: "..servers[i].." failed was " .. pingstats:getn(-1) .. " " .. pingstats:getn(-2) .. " " .. pingstats:getn(-3))
		end
		shaper:update()
	end

	if host_up_count < tonumber( opts["r"]) then
		score = score - 1
		if score < nb_up then score = 0 end 
		if score == nb_up then
			if shaper.losttimestamp == nil then
	    			log(string.format("Interface %s (%s) is offline", opts["i"], opts["d"]))
	   			-- exec hotplug iface
				run(string.format("/usr/sbin/track.sh ifdown %s %s", opts["i"], opts["d"]))
				-- clear QoS on interface down
				shaper:disableQos()
				losttimestamp = nil

				score = 0
			else
			        local dlspeed = bw_stats:avgdownload(shaper.losttimestamp - 2)
				local upspeed = bw_stats:avgupload(shaper.losttimestamp - 2)
			        if (dlspeed ~= nil and dlspeed < mindownload) or (upspeed ~= nil and upspeed < minupload) then
		    			log(string.format("Interface %s (%s) is offline", opts["i"], opts["d"]))
		   			-- exec hotplug iface
					run(string.format("/usr/sbin/track.sh ifdown %s %s", opts["i"], opts["d"]))
					-- clear QoS on interface down
					shaper:disableQos()
					losttimestamp = nil

					score = 0
				else
					log(string.format("Interface %s (%s) lost his tracker but we still have some traffic (up %s kbit/s, dn %s kbit/s)", opts["i"], opts["d"], dlspeed, upspeed))
					losttimestamp = os.time()

					lost = 0
					score = score + 1
				end
			end
		end
	else
		if score < init_score and lost > 0 then
			losttimestamp = nil
			log(string.format("Lost %d ping(s) ont interface %s (%s)", (lost * opts["c"]), opts["i"], opts["d"]))
		end

		score = score + 1
		lost = 0

		if score > nb_up then score = init_score end
		if score == nb_up then
			log(string.format("Interface %s (%s) is online", opts["i"],    opts["d"]))
			-- exec hotplug iface	
			run(string.format("/usr/sbin/track.sh ifup %s %s", opts["i"], opts["d"]))
			shaper:enableQos()
		end
	end


	host_up_count=0
	-- sleep interval asked
	p.sleep( opts["v"] )
end