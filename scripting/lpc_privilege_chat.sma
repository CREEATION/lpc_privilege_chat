#include <amxmodx>
#include <amxmisc>

#define VERSION "4.0c"

#define MAX_TAGS 16
#define MAX_TAG_LENGTH 32
#define MAX_MSG_LENGTH 192

#define TASK_TAGINDEX 6892

/**
 * Whisper commands
 */
new a_RegisterCmds[][] = {
	"pm", "/pm", "!pm", ".pm",
	"whisper", "/whisper", "!whisper", ".whisper",
	"psay", "/psay", "!psay", ".psay",
	"msg", "/msg", "!msg", ".msg"
}

/**
 * Channel String Formats
 */
// public message (username, message)
#define CHATMSG_ALL "^3%s^1 :  %s"
// dead public message (username, message)
#define CHATMSG_DEAD "^1*DEAD* ^3%s^1 :  %s"
// public spec message (username, message)
#define CHATMSG_SPEC "^1*SPEC* ^3%s^1 :  %s"
// team message (team, username, message)
#define CHATMSG_TEAM "^1(%s) ^3%s^1 :  %s"
// dead team message (team, username, message)
#define CHATMSG_TEAMDEAD "^1*DEAD*(%s) ^3%s^1 :  %s"

// whisper format (sendername, message)
#define CHATMSG_WHISPER "^4* ^3%s ^4whispers^1 :  %s"
#define CHATMSG_WHISPER_USER "^4* ^3You ^4whispered to ^3%s^1 :  %s"
// how admins see a whisper message (sendername, recievername, message)
#define CHATMSG_WHISPER_ADMIN "^4* ^3%s ^4whispered to ^3%s^1 :  ^4%s"
// whisper error when user not found (username)
#define CHATMSG_WHISPER_NOTFOUND "^4[Whisper] ^1Error: ^3User ^"^4%s^3^" not found or you need to be more specific"
// whisper error when more than 2 users found
#define CHATMSG_WHISPER_MULTIPLE "^4[Whisper] ^1Error: ^4%d Users ^3found, you need to be more specific"
// whisper error when user send himself a message (no arguments)
#define CHATMSG_WHISPER_SELF "^4[Whisper] ^1Error: ^3You can't whisper to yourself :("
// whisper error when user send a message to alive player while dead
#define CHATMSG_WHISPER_DEAD "^4[Whisper] ^1Error: ^3You can't whisper to alive players because you're dead"

// adminchat format (username, message)
#define ADMINCHATMSG_ADMIN "^4[^1!^4] ^3%s ^4reports^1 :  %s"
#define ADMINCHATMSG_USER "^4[^1!^4] ^3You ^4reported^1 :  %s"

/**
 * ==================================
 * >>>>> DON'T EDIT BELOW HERE! <<<<<
 * (unless ya know what you're doing)
 *    (i don't know either though)
 * ==================================
 */

#define MAX_PLAYERS 32

new g_ConfigsDir[128], g_FilePointer,
	g_MsgSayText, g_MaxPlayers

new Array:g_Flags,
	Array:g_Tags,
	Array:g_TagColors,
	Array:g_NameColors,
	Array:g_MsgColors,
	Array:g_ShowChat,
	Array:g_TeamStrings

new g_PlayerTagIndex[MAX_PLAYERS+1]

new lpc_chat_enable, lpc_chat_team_ct, lpc_chat_team_t, lpc_chat_team_spec

public plugin_init()
{
	register_plugin( "LPC Privilege Chat", VERSION, "CREE7EN." )

	// block default hud messages
	set_msg_block( get_user_msgid("HudTextArgs"), BLOCK_SET )

	// events
	register_logevent( "event_round_start", 2, "0=World triggered", "1=Round_Start" )

	// hook all chat messages
	register_clcmd( "say", "hook_user_say" )
	register_clcmd( "say_team", "hook_user_sayteam" )

	g_MsgSayText = get_user_msgid("SayText")
	g_MaxPlayers = get_maxplayers()

	lpc_chat_enable = register_cvar( "lpc_chat_enable", "1", FCVAR_SPONLY | FCVAR_UNLOGGED )
	lpc_chat_team_ct = register_cvar( "lpc_chat_team_ct", "Counter-Terrorist", FCVAR_SPONLY | FCVAR_UNLOGGED )
	lpc_chat_team_t = register_cvar( "lpc_chat_team_t", "Terrorist", FCVAR_SPONLY | FCVAR_UNLOGGED )
	lpc_chat_team_spec = register_cvar( "lpc_chat_team_spec", "Spectator", FCVAR_SPONLY | FCVAR_UNLOGGED )

	get_configsdir( g_ConfigsDir, 127 )
	server_cmd( "exec %s/_LPC/lpc_chat.cfg", g_ConfigsDir )
}

public event_round_start()
{
	new a_Players[MAX_PLAYERS], n_Players
	get_players( a_Players, n_Players, "ch" )

	for ( new i; i < n_Players; i++ )
	{
		task_set_tagindex( a_Players[i] + TASK_TAGINDEX )
	}

	return PLUGIN_CONTINUE
}

public client_putinserver( p_userid )
{
	task_set_tagindex( p_userid + TASK_TAGINDEX )
}

public client_authorized( p_userid )
{
	task_set_tagindex( p_userid + TASK_TAGINDEX )
}

public client_infochanged( p_userid )
{
	if ( task_exists( p_userid + TASK_TAGINDEX ) )
		remove_task( p_userid + TASK_TAGINDEX )

	set_task( 0.1, "task_set_tagindex", p_userid + TASK_TAGINDEX )
}

public task_set_tagindex( p_userid )
{
	p_userid -= TASK_TAGINDEX

	g_PlayerTagIndex[p_userid] = 0

	// get right formatting according to user rights
	new s_Flags[27],
		n_Flags = ArraySize(g_Flags)

	for ( new i = n_Flags-1; i > 0; i-- )
	{
		if ( 0 <= i < n_Flags )
			ArrayGetString( g_Flags, i, s_Flags, 26 )

		if ( get_user_flags(p_userid) == read_flags(s_Flags) )
			g_PlayerTagIndex[p_userid] = i
	}

	return
}

public client_disconnect( p_userid )
{
	g_PlayerTagIndex[p_userid] = 0
}

public hook_user_say( p_userid )
{
	if ( !is_user_connected(p_userid) )
		return PLUGIN_HANDLED

	if ( !get_pcvar_num(lpc_chat_enable) )
		return PLUGIN_CONTINUE

	new s_Message[MAX_MSG_LENGTH]
	clean_message(s_Message)

	if ( !s_Message[0] )
		return PLUGIN_HANDLED

	// skip hud messages, but let through "@@@@ text" mistakes (yes, i'm stupid)
	if (
		(
			(s_Message[0] == '@' && s_Message[1] != '@') ||
			(s_Message[0] == '@' && s_Message[1] == '@' && s_Message[2] != '@') ||
			(s_Message[0] == '@' && s_Message[1] == '@' && s_Message[2] == '@' && s_Message[3] != '@')
		)
		&& get_user_flags(p_userid) & ADMIN_CHAT
	)
	{
		return PLUGIN_CONTINUE
	}

	// process whisper messages
	if ( is_whisper_message( s_Message ) )
	{
		user_whisper( p_userid, s_Message )
		return PLUGIN_HANDLED
	}

	user_output_text( p_userid, false, get_user_team(p_userid), s_Message )

	return PLUGIN_HANDLED
}

public hook_user_sayteam( p_userid )
{
	if ( !is_user_connected(p_userid) )
		return PLUGIN_HANDLED

	if ( !get_pcvar_num(lpc_chat_enable) )
		return PLUGIN_CONTINUE

	new s_Message[MAX_MSG_LENGTH]
	clean_message(s_Message)

	if ( !s_Message[0] )
		return PLUGIN_HANDLED

	// process whisper messages
	if ( is_whisper_message( s_Message ) )
	{
		user_whisper( p_userid, s_Message )
		return PLUGIN_HANDLED
	}

	new MessageType = 1

	// is team message and starts with @? (adminchat)
	if ( s_Message[0] == '@' )
	{
		MessageType = 2
		format( s_Message, MAX_MSG_LENGTH-1, s_Message[1] )
		trim(s_Message)
	}

	user_output_text( p_userid, true, get_user_team(p_userid), s_Message, MessageType )

	return PLUGIN_HANDLED
}

public user_whisper( p_userid, const p_msg[] )
{
	if ( !is_user_connected(p_userid) )
		return PLUGIN_HANDLED

	new s_Sendername[32], t_Empty[1], s_Recievername[32], s_Message[MAX_MSG_LENGTH],
		s_MsgFormat[MAX_MSG_LENGTH]

	// get username and clean up
	parse( p_msg, t_Empty, 0, s_Recievername, 31 )
	remove_quotes(s_Recievername)
	trim(s_Recievername)

	if ( !s_Recievername[0] )
		return PLUGIN_HANDLED

	// get message and clean up
	split( p_msg, t_Empty, 0, s_Message, MAX_MSG_LENGTH-1, s_Recievername )
	if ( s_Message[0] == '"' ) replace( s_Message, MAX_MSG_LENGTH-1, "^"", "" )
	trim(s_Message)

	// get all matching clients
	new a_Recievers[MAX_PLAYERS], n_Recievers
	get_players( a_Recievers, n_Recievers, "cfgh", s_Recievername )

	new i_Reciever = a_Recievers[0]

	// multiple clients with the same name found...
	if ( n_Recievers >= 2 )
	{
		new i_IsExactMatch,
			s_TempRecieverName[32]

		for ( new i; i < n_Recievers; i++ )
		{
			get_user_name( a_Recievers[i], s_TempRecieverName, 31 )

			if ( equal( s_Recievername, s_TempRecieverName ) )
			{
				i_IsExactMatch = a_Recievers[i]
				break
			}
		}

		if ( !i_IsExactMatch )
		{
			if ( p_userid == a_Recievers[0] ) i_Reciever = a_Recievers[1]; n_Recievers--
			if ( p_userid == a_Recievers[1] ) i_Reciever = a_Recievers[0]; n_Recievers--

			if ( n_Recievers >= 2 )
			{
				formatex( s_MsgFormat, MAX_MSG_LENGTH-1, CHATMSG_WHISPER_MULTIPLE, n_Recievers )
				message_write( p_userid, p_userid, s_MsgFormat )
				return PLUGIN_HANDLED
			}
		}
		else
		{
			i_Reciever = i_IsExactMatch
		}
	}

	// client not found, output error to sender
	if ( !i_Reciever || !is_user_connected(i_Reciever) )
	{
		formatex( s_MsgFormat, MAX_MSG_LENGTH-1, CHATMSG_WHISPER_NOTFOUND, s_Recievername )
		message_write( p_userid, p_userid, s_MsgFormat )
		return PLUGIN_HANDLED
	}

	// he send a message to himself... knew it
	if ( p_userid == i_Reciever )
	{
		message_write( p_userid, p_userid, CHATMSG_WHISPER_SELF )
		return PLUGIN_HANDLED
	}

	// get sender name
	get_user_name( p_userid, s_Sendername, charsmax(s_Sendername) )
	// get reciever name
	get_user_name( i_Reciever, s_Recievername, charsmax(s_Recievername) )

	// players cant message alive players when dead
	if ( !is_user_alive(p_userid) && is_user_alive(i_Reciever) )
	{
		if ( get_user_showchat(p_userid) <= 0 )
		{
			message_write( p_userid, p_userid, CHATMSG_WHISPER_DEAD )
			return PLUGIN_HANDLED
		}
	}

	// format and output whisper message as confirmation to sender
	formatex( s_MsgFormat, MAX_MSG_LENGTH-1, CHATMSG_WHISPER_USER, s_Recievername, s_Message )
	message_write( p_userid, p_userid, s_MsgFormat )

	// format and output whisper message for reciever
	formatex( s_MsgFormat, MAX_MSG_LENGTH-1, CHATMSG_WHISPER, s_Sendername, s_Message )
	message_write( p_userid, i_Reciever, s_MsgFormat )

	// show whisper to admins too
	new a_Players[MAX_PLAYERS], n_Players
	get_players( a_Players, n_Players, "c" )

	// format message for admins who can see it
	formatex( s_MsgFormat, MAX_MSG_LENGTH-1, CHATMSG_WHISPER_ADMIN, s_Sendername, s_Recievername, s_Message )

	for ( new i; i < n_Players; i++ )
		if ( i_Reciever != a_Players[i] && p_userid != a_Players[i] && get_user_showchat(a_Players[i]) == 4 )
			message_write( p_userid, a_Players[i], s_MsgFormat )

	return PLUGIN_HANDLED
}

/***************************************************************************************
 * Stocks
 */
stock is_whisper_message( const p_msg[] )
{
	new s_MsgLeft[16], s_MsgRight[1],
		bool:b_Whisper = false

	// get left portion of the message
	strtok( p_msg, s_MsgLeft, 15, s_MsgRight, 0 )

	for ( new i; i < sizeof a_RegisterCmds; i++ )
	{
		// only process if it is indeed a whisper command
		if ( !equali( s_MsgLeft, a_RegisterCmds[i] ) )
			continue

		b_Whisper = true
	}

	return b_Whisper
}

stock user_output_text( p_userid, bool:p_teammsg=false, p_teamid, p_msg[], p_type=1 )
{
	if ( !is_user_connected(p_userid) )
		return PLUGIN_HANDLED

	// if it's an admin message, show to admins
	if ( p_type == 2 )
	{
		user_output_adminchat( p_userid, p_msg )
		return PLUGIN_HANDLED
	}

	// get username
	new s_Username[32]
	get_user_name( p_userid, s_Username, 31 )

	// format the message correctly
	format_message( p_userid, p_teammsg, p_teamid, p_msg )

	new i_Alive = is_user_alive(p_userid),
		i_RecieverShowChat, i_RecieverAlive, i_RecieverTeam

	new a_Players[MAX_PLAYERS], n_Players
	get_players( a_Players, n_Players, "c" )

	for ( new i; i < n_Players; i++ )
	{
		i_RecieverShowChat = get_user_showchat(a_Players[i])
		i_RecieverAlive = is_user_alive(a_Players[i])
		i_RecieverTeam = get_user_team(a_Players[i])

		if (
			// show to self and owner
			(p_userid == a_Players[i] || i_RecieverShowChat == 4) ||
			// show public dead/alive messages
			(i_RecieverShowChat == 3 && !p_teammsg) ||
			// show public alive messages
			(i_RecieverShowChat == 2 && !p_teammsg && i_Alive) ||
			// show public dead messages
			(i_RecieverShowChat == 1 && !p_teammsg && !i_Alive) ||
			// show public alive messages, if also alive
			(i_RecieverShowChat == 0 && !p_teammsg && i_Alive && i_RecieverAlive) ||
			// show public dead messages, if also dead
			(i_RecieverShowChat == 0 && !p_teammsg && !i_Alive && !i_RecieverAlive) ||
			// show alive team messages, if also alive
			(i_RecieverShowChat == 0 && p_teammsg && p_teamid == i_RecieverTeam && i_Alive && i_RecieverAlive) ||
			// show dead team messages, if also dead
			(i_RecieverShowChat == 0 && p_teammsg && p_teamid == i_RecieverTeam && !i_Alive && !i_RecieverAlive)
			)
		{
			message_write( p_userid, a_Players[i], p_msg )
		}
	}

	message_log_chat( p_userid, p_msg )

	return 1
}

stock user_output_adminchat( p_userid, const p_msg[] )
{
	if ( !is_user_connected(p_userid) )
		return PLUGIN_HANDLED

	new s_MsgFormat[MAX_MSG_LENGTH],
		s_Sendername[32]

	// get sender name
	get_user_name( p_userid, s_Sendername, 31 )

	// format and output for user as confirmation
	formatex( s_MsgFormat, MAX_MSG_LENGTH-1, ADMINCHATMSG_USER, p_msg )

	message_write( p_userid, p_userid, s_MsgFormat )

	// show message to all admins
	formatex( s_MsgFormat, MAX_MSG_LENGTH-1, ADMINCHATMSG_ADMIN, s_Sendername, p_msg )
	message_log_chat( p_userid, s_MsgFormat )

	new a_Players[MAX_PLAYERS], n_Players
	get_players( a_Players, n_Players, "c" )

	for ( new i; i < n_Players; i++ )
	{
		// skip own admin message
		if ( p_userid == a_Players[i] && get_user_flags(a_Players[i]) & ADMIN_CHAT )
			continue

		if ( get_user_flags(a_Players[i]) & ADMIN_CHAT )
			message_write( p_userid, a_Players[i], s_MsgFormat )
	}

	return 1
}

stock bool:is_user_steam( p_userid )
{
	static dp_pointer

	if (dp_pointer || (dp_pointer = get_cvar_pointer("dp_r_id_provider")) )
	{
		server_cmd( "dp_clientinfo %d", p_userid )
		server_exec()

		return get_pcvar_num(dp_pointer) == 2 ? true : false
	}

	new szAuthid[34]
	get_user_authid(p_userid, szAuthid, charsmax(szAuthid))

	return ( containi(szAuthid, "LAN") < 0 )
}


stock format_message( p_userid, bool:p_teammsg=false, p_teamid, p_msg[] )
{
	if ( !is_user_connected(p_userid) )
		return PLUGIN_HANDLED

	// set tag color
	new s_Tag[MAX_TAG_LENGTH]
	ArrayGetString( g_Tags, g_PlayerTagIndex[p_userid], s_Tag, MAX_TAG_LENGTH-1 )

	// replace custom tag colors
	replace_all( s_Tag, MAX_TAG_LENGTH-1, "!d", "^1" )
	replace_all( s_Tag, MAX_TAG_LENGTH-1, "!t", "^3" )
	replace_all( s_Tag, MAX_TAG_LENGTH-1, "!g", "^4" )

	switch ( ArrayGetCell( g_TagColors, g_PlayerTagIndex[p_userid] ) )
	{
		case 1: format( s_Tag, MAX_TAG_LENGTH-1, "^1%s", s_Tag )
		case 2: format( s_Tag, MAX_TAG_LENGTH-1, "^3%s", s_Tag )
		case 3: format( s_Tag, MAX_TAG_LENGTH-1, "^4%s", s_Tag )
		default: format( s_Tag, MAX_TAG_LENGTH-1, "^1%s", s_Tag )
	}

	if ( !is_user_steam(p_userid) && !(get_user_flags(p_userid) & ADMIN_LEVEL_H) ) {
		format( s_Tag, MAX_TAG_LENGTH-1, "^1[Non-Steam] %s", s_Tag )
	}

	// set name color
	new s_Username[32+MAX_TAG_LENGTH]
	get_user_name( p_userid, s_Username, 31+MAX_TAG_LENGTH )
	switch ( ArrayGetCell( g_NameColors, g_PlayerTagIndex[p_userid] ) )
	{
		case 1: format( s_Username, 31+MAX_TAG_LENGTH, "^1%s", s_Username )
		case 2: format( s_Username, 31+MAX_TAG_LENGTH, "^3%s", s_Username )
		case 3: format( s_Username, 31+MAX_TAG_LENGTH, "^4%s", s_Username )
		default: format( s_Username, 31+MAX_TAG_LENGTH, "^3%s", s_Username )
	}

	// set message color
	new s_Msg[MAX_MSG_LENGTH]
	switch ( ArrayGetCell( g_MsgColors, g_PlayerTagIndex[p_userid] ) )
	{
		case 1: formatex( s_Msg, MAX_MSG_LENGTH-1, "^1%s", p_msg )
		case 2: formatex( s_Msg, MAX_MSG_LENGTH-1, "^3%s", p_msg )
		case 3: formatex( s_Msg, MAX_MSG_LENGTH-1, "^4%s", p_msg )
		default: formatex( s_Msg, MAX_MSG_LENGTH-1, "^1%s", p_msg )
	}

	// get team string
	new s_TeamString[32]
	ArrayGetString( g_TeamStrings, p_teamid, s_TeamString, 31 )

	// append username to tag
	format( s_Username, 31+MAX_TAG_LENGTH, "%s%s", s_Tag, s_Username )

	// format the message nao
	new s_MsgFormat[MAX_MSG_LENGTH]

	// user is in the game (not spectator)
	if ( p_teamid != 0 && p_teamid != 3 )
	{
		new i_Alive = is_user_alive(p_userid)

		// team message
		if ( !p_teammsg )
		{
			// is public message && alive
			if ( i_Alive )
				formatex( s_MsgFormat, MAX_MSG_LENGTH-1, CHATMSG_ALL, s_Username, s_Msg )
			// is public message && dead
			else
				formatex( s_MsgFormat, MAX_MSG_LENGTH-1, CHATMSG_DEAD, s_Username, s_Msg )
		}
		else
		{
			// is team message && alive
			if ( i_Alive )
				formatex( s_MsgFormat, MAX_MSG_LENGTH-1, CHATMSG_TEAM, s_TeamString, s_Username, s_Msg )
			// is team message && dead
			else
				formatex( s_MsgFormat, MAX_MSG_LENGTH-1, CHATMSG_TEAMDEAD, s_TeamString, s_Username, s_Msg )
		}
	}
	// user is spectator
	else
	{
		if ( !p_teammsg )
			formatex( s_MsgFormat, MAX_MSG_LENGTH-1, CHATMSG_SPEC, s_Username, s_Msg )
		else
			formatex( s_MsgFormat, MAX_MSG_LENGTH-1, CHATMSG_TEAM, s_TeamString, s_Username, s_Msg )
	}

	// replace original message
	copy( p_msg, MAX_MSG_LENGTH-1, s_MsgFormat )

	return 1
}

stock get_user_showchat( p_userid )
{
	if ( !is_user_connected(p_userid) )
		return PLUGIN_HANDLED

	new s_Flags[27], n_Flags = ArraySize(g_Flags)

	for ( new i = 0; i <= n_Flags; i++ )
	{
		if ( 0 <= i < n_Flags )
			ArrayGetString( g_Flags, i, s_Flags, 26 )

		if ( get_user_flags(p_userid) == read_flags(s_Flags) )
			return ArrayGetCell( g_ShowChat, i )
	}

	return 0
}

stock message_write( p_userid, p_reciever, const p_msg[] )
{
	if ( !is_user_connected(p_userid) || !is_user_connected(p_reciever) )
		return PLUGIN_HANDLED

	// actually write the message now
	emessage_begin( p_userid ? MSG_ONE_UNRELIABLE : MSG_BROADCAST, g_MsgSayText, _, p_reciever )
	ewrite_byte( p_userid ? p_userid : ( g_MaxPlayers + 1 ) )
	ewrite_string(p_msg)
	emessage_end()

	return 1
}

stock message_log_chat( p_userid, p_msg[] )
{
	if ( !is_user_connected(p_userid) )
		return PLUGIN_HANDLED

	static i_UserId, i_Team
	new s_Username[32], s_UserAuthId[32], s_MsgCmd[9]
	get_user_authid( p_userid, s_UserAuthId, 31 )
	get_user_name( p_userid, s_Username, 31 )
	i_UserId = get_user_userid(p_userid)
	i_Team = get_user_team(p_userid)
	// get used chat command (say/say_team)
	read_argv( 0, s_MsgCmd, 8 )
	// get raw message
	new s_RawMsg[MAX_MSG_LENGTH], t_Left[1]
	split( p_msg, t_Left, 0, s_RawMsg, MAX_MSG_LENGTH-1, " :  " )

	new s_Team[3]
	switch ( i_Team )
	{
		case 0: formatex( s_Team, 2, "S" )
		case 1: formatex( s_Team, 2, "T" )
		case 2: formatex( s_Team, 2, "CT" )
		case 3: formatex( s_Team, 2, "S" )
	}

	server_print( p_msg )
	log_message( "^"%s<%d><%s><%s>^" %s ^"%s^"", s_Username, i_UserId, s_UserAuthId, s_Team, s_MsgCmd, s_RawMsg )

	return 1
}

stock clean_message( p_msg[] )
{
	read_args( p_msg, MAX_MSG_LENGTH-1 )

	// clean up message
	remove_quotes(p_msg)
	trim(p_msg)
	replace_all( p_msg, MAX_MSG_LENGTH-1, "#", "＃" )
	replace_all( p_msg, MAX_MSG_LENGTH-1, "%", "％" )
	// replace_all( p_msg, MAX_MSG_LENGTH-1, ";", "；" ) // doesn't work :C

	return 1
}

// https://forums.alliedmods.net/showpost.php?p=2196204&postcount=7
stock bool:substr( dst[], const size, const src[], start, len = 0 )
{
	new srclen = strlen(src)
	start = (start < 0) ? srclen + start : start

	if ( start < 0 || start > srclen )
		return false

	if ( len == 0 )
		len = srclen
	else if ( len < 0 )
	{
		if ( (len = srclen - start + len) < 0 )
			return false
	}

	len = min(len, size)

	copy(dst, len, src[start])

	return true
}

public plugin_end()
{
	ArrayDestroy(g_Flags)
	ArrayDestroy(g_Tags)
	ArrayDestroy(g_TagColors)
	ArrayDestroy(g_NameColors)
	ArrayDestroy(g_MsgColors)
	ArrayDestroy(g_ShowChat)
}

public plugin_precache()
{
	get_configsdir( g_ConfigsDir, 127 )
	format( g_ConfigsDir, 127, "%s/_LPC/lpc_privilege_chat.ini", g_ConfigsDir )

	// create arrays
	g_Flags = ArrayCreate( 27, MAX_TAGS )
	g_Tags = ArrayCreate( MAX_TAG_LENGTH, MAX_TAGS )
	g_TagColors = ArrayCreate( 1, MAX_TAGS )
	g_NameColors = ArrayCreate( 1, MAX_TAGS )
	g_MsgColors = ArrayCreate( 1, MAX_TAGS )
	g_ShowChat = ArrayCreate( 1, MAX_TAGS )

	// push defaults for normal users
	ArrayPushString( g_Flags, "z" )
	ArrayPushString( g_Tags, "" )
	ArrayPushCell( g_TagColors, 1 )
	ArrayPushCell( g_NameColors, 2 )
	ArrayPushCell( g_MsgColors, 1 )
	ArrayPushCell( g_ShowChat, 0 )

	// read and set team strings from config
	new s_TeamCT[32], s_TeamT[32], s_TeamSpec[32]

	lpc_chat_enable = register_cvar( "lpc_chat_enable", "1", FCVAR_SPONLY | FCVAR_UNLOGGED )
	lpc_chat_team_ct = register_cvar( "lpc_chat_team_ct", "Team", FCVAR_SPONLY | FCVAR_UNLOGGED )
	lpc_chat_team_t = register_cvar( "lpc_chat_team_t", "Team", FCVAR_SPONLY | FCVAR_UNLOGGED )
	lpc_chat_team_spec = register_cvar( "lpc_chat_team_spec", "Team", FCVAR_SPONLY | FCVAR_UNLOGGED )

	get_pcvar_string( lpc_chat_team_ct, s_TeamCT, 31 )
	get_pcvar_string( lpc_chat_team_t, s_TeamT, 31 )
	get_pcvar_string( lpc_chat_team_spec, s_TeamSpec, 31 )

	g_TeamStrings = ArrayCreate( 32, 4 )
	ArrayPushString( g_TeamStrings, s_TeamSpec )
	ArrayPushString( g_TeamStrings, s_TeamT )
	ArrayPushString( g_TeamStrings, s_TeamCT )
	ArrayPushString( g_TeamStrings, s_TeamSpec )

	// process config file
	g_FilePointer = fopen( g_ConfigsDir, "r" )

	if ( !g_FilePointer )
		abort( AMX_ERR_NATIVE, "[LPC] Configuration File (%s) not found", g_ConfigsDir )

	new s_Line[128], i_Line = 1

	while ( !feof(g_FilePointer) )
	{
		fgets( g_FilePointer, s_Line, 127 )
		replace( s_Line, 127, "^n", "" )
		trim(s_Line)

		// skip comments and empty lines
		if ( !s_Line[0] || s_Line[0] == ';' )
			continue

		new s_LineCurrent[128], s_LineArg = 1

		while (s_Line[0] != 0 && strtok(s_Line, s_LineCurrent, 127, s_Line, 127, '"'))
		{
			trim(s_LineCurrent)

			if ( !s_LineCurrent[0] )
				continue

			switch ( s_LineArg )
			{
				case 1:
				{
					new s_Tag[MAX_TAG_LENGTH]
					formatex( s_Tag, MAX_TAG_LENGTH-1, "%s ", s_LineCurrent )
					ArrayPushString( g_Tags, s_Tag )
				}
				case 2: ArrayPushString( g_Flags, s_LineCurrent )
				case 3:
				{
					new s_TagColor[2], s_NameColor[2], s_MsgColor[2]

					substr( s_TagColor, 1, s_LineCurrent, 0, 1 )
					substr( s_NameColor, 1, s_LineCurrent, 1, 1 )
					substr( s_MsgColor, 1, s_LineCurrent, 2, 1 )

					ArrayPushCell( g_TagColors, str_to_num(s_TagColor) )
					ArrayPushCell( g_NameColors, str_to_num(s_NameColor) )
					ArrayPushCell( g_MsgColors, str_to_num(s_MsgColor) )
				}
				case 4: ArrayPushCell( g_ShowChat, str_to_num(s_LineCurrent) )
			}

			s_LineArg++
		}

		i_Line++
	}

	fclose(g_FilePointer)
}
