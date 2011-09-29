-- -*- mode: Lua; lua-indent-level: 8; indent-tabs-mode: t; -*-
-- ************************************************************************** --
--  FreePOPs @spray.se and @home.se webmail interface
-- 
--  $Id$
-- 
--  Released under the GNU/GPL license
--  Written by Mikael Magnusson <mikma@user.sourceforge.net>
-- ************************************************************************** --

PLUGIN_VERSION = "0.0.1"
PLUGIN_NAME = "Spray web mail"
PLUGIN_REQUIRE_VERSION = "0.2.0"
PLUGIN_LICENSE = "GNU/GPL"
PLUGIN_URL = "http://www.freepops.org/"
PLUGIN_HOMEPAGE = "http://www.freepops.org"
PLUGIN_AUTHORS_NAMES = {"Mikael Magnusson"}
PLUGIN_AUTHORS_CONTACTS = {"mikma@user.sourceforge.net"}
PLUGIN_DOMAINS = {"@spray.se", "@home.se"}
-- PLUGIN_REGEXES = {"@..."}
PLUGIN_PARAMETERS = { 
	{name="--name--", description={en="--desc--",it=="--desc--"}},
}
PLUGIN_DESCRIPTIONS = {
	en=[[----]]
}


foo_globals= {
   username="nothing",
   password="nothing",
	stat_done = false,

   -- Server URL
   --
   strLoginUrl = "http://idlogin.spray.se/mail",
   strInboxUrl = "http://nymail.spray.se/mail/ms_ajax.asp?folder=/Inbox&pg=1&msgno=25&sortby=Received&sort_order=DESC&dtTS=full&JSON=yes&BusyEmptyTrash=false&bBusyEmptyJunk=false",
   strDownloadUrl = "http://nymail.spray.se/tools/getFile.asp?GUID=%s&MsgID=%s&Show=3&ForceDownload=1&name=X*1&MsgFormat=txt&Headers=true",
   strActionUrl = "http://nymail.spray.se/mail/mail_action.asp"
}

-- ************************************************************************** --
-- 
-- This is the interface to the external world. These are the functions 
-- that will be called by FreePOPs.
--
-- param pstate is the userdata to pass to (set|get)_popstate_* functions
-- param username is the mail account name
-- param password is the account password
-- param msg is the message number to operate on (may be decreased dy 1)
-- param pdata is an opaque data for popserver_callback(buffer,pdata) 
-- 
-- return POPSERVER_ERR_*
-- 
-- ************************************************************************** --

-- Is called to initialize the module
function init(pstate)
	freepops.export(pop3server)
	
	log.dbg("FreePOPs plugin '"..
		PLUGIN_NAME.."' version '"..PLUGIN_VERSION.."' started!\n")

	-- the serialization module
	require("serial")

	-- the browser module
	require("browser")

	-- the common module
	require("common")

	-- checks on globals
	freepops.set_sanity_checks()
		
	return POPSERVER_ERR_OK
end
-- -------------------------------------------------------------------------- --
-- Must save the mailbox name
function user(pstate,username)
	foo_globals.username = username
	--print("*** the user wants to login as '"..username.."'")
	return POPSERVER_ERR_OK
end


-- -------------------------------------------------------------------------- --
-- Must login
function pass(pstate,password)

	-- save the password
	foo_globals.password = password

	--print("*** the user inserted '"..password..
	--	"' as the password for '"..foo_globals.username.."'")

	-- eventually load sessions
	local s = session.load_lock(key())

	-- check if loaded properly
	if s ~= nil then
		-- "\a" means locked
		if s == "\a" then
			log.say("Session for "..foo_globals.name..
				" is already locked\n")
			return POPSERVER_ERR_LOCKED
		end

		-- load the session
		local c,err = loadstring(s)
		if not c then
			log.error_print("Unable to load saved session: "..err)
			return foo_login()
		end

		-- exec the code loaded from the session string
		c()

		log.say("Session loaded for " .. foo_globals.username ..
			"(" .. foo_globals.session_id .. ")\n")
		return POPSERVER_ERR_OK
	else
		-- call the login procedure
		return foo_login()
	end
end

	
function foo_login()
	-- create a new browser
	local b = browser.new()
	-- store the browser object in globals
	foo_globals.browser = b
-- 	b:verbose_mode()

	-- create the data to post
	local post_data = string.format("username=%s&password=%s",
		foo_globals.username,foo_globals.password)
	-- the uri to post to
	local post_uri = foo_globals.strLoginUrl

	-- post it
	local file,err = nil, nil
	file,err = b:post_uri(post_uri,post_data)

	if file == nil then 
	   print("we received this error: ".. err)
		return POPSERVER_ERR_AUTH
	end

	local cookie = b:get_cookie("loggedin")
	if not cookie then
	   print("we weren't logged in: no cookie")
	   return POPSERVER_ERR_AUTH
	end

	--print("we received this webpage: ".. file)

	-- search the session ID
	-- -- local id = string.match(file,"session_id=(%w+)")

	-- -- if id == nil then 
	-- -- 	return POPSERVER_ERR_AUTH
	-- -- end

	-- Get GUID cookie
	local cookie = b:get_cookie("GUID")
	local id
	if cookie then
	   id = cookie and curl.unescape(cookie.value)
	end
	if not id then
	   log.say("Login Failed - Session not initialized.\n")
	   return POPSERVER_ERR_AUTH
	end
	   
	print("we are logged in: " .. id)

	foo_globals.session_id = id

	return POPSERVER_ERR_OK
end
-- -------------------------------------------------------------------------- --
-- Must quit without updating
function quit(pstate)
	session.unlock(key())
	return POPSERVER_ERR_OK
end
-- -------------------------------------------------------------------------- --
-- Update the mailbox status and quit
function quit_update(pstate)
   -- FIXME
	-- we need the stat
	local st = stat(pstate)
	if st ~= POPSERVER_ERR_OK then return st end

	-- shorten names, not really important
	local b = foo_globals.browser
	local post_uri = foo_globals.strActionUrl
	local session_id = foo_globals.session_id
	-- Move to trash
	local post_data = "Action=0&folder=/Inbox&MsgIDs="

	-- here we need the stat, we build the uri and we check if we 
	-- need to delete something
	local delete_something = false;
	
	for i=1,get_popstate_nummesg(pstate) do
		if get_mailmessage_flag(pstate,i,MAILMESSAGE_DELETE) then
			post_data = post_data .. "|" ..
				get_mailmessage_uidl(pstate,i)
			delete_something = true	
		end
	end

	if delete_something then
		b:post_uri(post_uri,post_data)
	end

	-- save fails if it is already saved
	session.save(key(),serialize_state(),session.OVERWRITE)
	-- unlock is useless if it have just been saved, but if we save
	-- without overwriting the session must be unlocked manually
	-- since it would fail instead overwriting
	session.unlock(key())

	return POPSERVER_ERR_OK
end
-- -------------------------------------------------------------------------- --
-- Fill the number of messages and their size
function stat(pstate)
	if foo_globals.stat_done == true then return POPSERVER_ERR_OK end
	
	local file,err = nil, nil
	local b = foo_globals.browser
	file,err = b:get_uri(foo_globals.strInboxUrl)

	local x = split(file, "_#r|-")

	--debug print
	--x:print()

	set_popstate_nummesg(pstate,table.getn(x))

	-- Fixme
	for i=1,table.getn(x) do
	   local c = split(x[i], "_#c|-")
	   local uidl = c[1]
	   local size = c[8]

	   if size == nil then
	      break
	   end

	   print("ID: " .. uidl)
	   print("Size: " .. size)

	   set_mailmessage_size(pstate,i,tonumber(size))
	   set_mailmessage_uidl(pstate,i,uidl)
	end

	foo_globals.stat_done = true
	return POPSERVER_ERR_OK
end

-- -------------------------------------------------------------------------- --
-- Fill msg uidl field
function uidl(pstate,msg)
	return common.uidl(pstate,msg)
end
-- -------------------------------------------------------------------------- --
-- Fill all messages uidl field
function uidl_all(pstate)
	return common.uidl_all(pstate)
end
-- -------------------------------------------------------------------------- --
-- Fill msg size
function list(pstate,msg)
	return common.list(pstate,msg)
end
-- -------------------------------------------------------------------------- --
-- Fill all messages size
function list_all(pstate)
	return common.list_all(pstate)
end
-- -------------------------------------------------------------------------- --
-- Unflag each message merked for deletion
function rset(pstate)
	return common.rset(pstate)
end
-- -------------------------------------------------------------------------- --
-- Mark msg for deletion
function dele(pstate,msg)
	return common.dele(pstate,msg)
end
-- -------------------------------------------------------------------------- --
-- Do nothing
function noop(pstate)
	return common.noop(pstate)
end

--------------------------------------------------------------------------------
-- The callbach factory for retr
--
function retr_cb(data)
	local a = stringhack.new()
	
	return function(s,len)
		s = a:dothack(s).."\0"
			
		popserver_callback(s,data)
			
		return len,nil
	end
end

-- -------------------------------------------------------------------------- --
-- Get first lines message msg lines, must call 
-- popserver_callback to send the data
function top(pstate,msg,lines,pdata)
   -- FIXME?
	return POPSERVER_ERR_OK

end

-- -------------------------------------------------------------------------- --
-- Get message msg, must call 
-- popserver_callback to send the data
function retr(pstate,msg,data)
		-- we need the stat
	local st = stat(pstate)
	if st ~= POPSERVER_ERR_OK then return st end

	--print("Enter retr: " .. msg)
	
	-- the callback
	local cb = retr_cb(data)
	
	-- some local stuff
	local b = foo_globals.browser
	local id = foo_globals.session_id
	local uidl = get_mailmessage_uidl(pstate,msg)
	local uri = string.format(foo_globals.strDownloadUrl, id, uidl)

	--print("Download: " .. uri)
	
	-- tell the browser to pipe the uri using cb
	local f,rc = b:pipe_uri(uri,cb)

	if not f then
	   log.error_print("Asking for "..uri.."\n")
	   log.error_print(rc.."\n")
	   print("Error f nil")
	   return POPSERVER_ERR_NETWORK
	else
	   popserver_callback("\r\n", data)
	end

	return POPSERVER_ERR_OK
end

--------------------------------------------------------------------------------
-- The key used to store session info
--
-- This key must be unique for all webmails, since the session pool is one
-- for all the webmails
--
function key()
	return foo_globals.username .. foo_globals.password
end


--------------------------------------------------------------------------------
-- Serialize the internal state
--
-- serial.serialize is not enough powerful to correctly serialize the
-- internal state. The field b is the problem. b is an object. This means
-- that it is a table (and no problem for this) that has some field that are
-- pointers to functions. this is the problem. there is no easy way for the
-- serial module to know how to serialize this. so we call b:serialize
-- method by hand hacking a bit on names
--
function serialize_state()
	foo_globals.stat_done = false;
	return serial.serialize("foo_globals",foo_globals) ..
	foo_globals.browser:serialize("foo_globals.browser")
end


-- ************************************************************************** --
--  Utility functions
-- ************************************************************************** --

-- From yahoo.lua
-- split str into parts separated by div
function split(str, div)
  if (div=='') then return false end
  local pos,arr = 0,{}
  -- for each divider found
  for st,sp in function() return string.find(str,div,pos,true) end do
    table.insert(arr,string.sub(str,pos,st-1)) -- chars left of divider
    pos = sp + 1 -- sp points to the last character in the divider
  end
  --table.insert(arr,string.sub(str,pos)) -- chars right of divider
  return arr
end

-- EOF
-- ************************************************************************** --
