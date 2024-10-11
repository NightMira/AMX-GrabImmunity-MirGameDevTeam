#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <engine>
#include <hamsandwich>
#include <nvault>

new const VERSION[ ] = "2.0"
new const TRKCVAR[ ] = "Grab_Y"

#define CLASSNAME "FrostEntity"

#define ADMIN ADMIN_LEVEL_A			// Граб
#define ADMIN_I ADMIN_IMMUNITY		// Иммунитет
#define ADMIN_GL ADMIN_RCON			// Обход иммунитета

#define F_WARNS ADMIN_BAN			// Флаг для возможности выдавать предупреждения
#define F_WARN_R ADMIN_RESERVATION	// Флаг для возможности забирать предупреждения
#define MAX_WARNS 5					// Максимум варнов (1=килл, 2=кик, 3=бан на 5м, 4=бан на 1ч, 5=бан на 1д)

#define SND_OFF		"kf/off.wav"
#define ON_MENU 	"kf/onn.wav"
#define SND_TASK	"kf/task.wav"

#define TSK_CHKE 50

#define SF_FADEOUT 0

new client_data[33][4]
#define GRABBED  0
#define GRABBER  1
#define GRAB_LEN 2
#define FLAGS    3

#define m_bitsDamageType 76

#define GRAB_MIN_DIST		90

#define CDF_IN_PUSH   (1<<0)
#define CDF_IN_PULL   (1<<1)
#define CDF_NO_CHOKE  (1<<2)

#define FROST_R		0
#define FROST_G		150
#define FROST_B		200

enum _: eFlagsAccess {
	eAccess,
	eImmunity,
	eAntiImmunity,
	eWarn,
	eWarnR,
	eName[32]
};

//Cvar Pointers
new p_players_only
new p_throw_force, p_min_dist, p_speed, p_grab_force
new p_choke_time, p_choke_dmg, p_auto_choke
new p_glow_r, p_glow_b, p_glow_g, p_glow_a
new p_fade, p_glow
new g_warns[ 33 ], g_vault

new const szPrefix[] = "^1[^4Grab^1]";

//Pseudo Constants
new MAXPLAYERS
new SVC_SCREENFADE, SVC_SCREENSHAKE, WTF_DAMAGE

new bool:g_bShowMenu[33], g_Freeze[33], g_immunity[33];

public plugin_init( )
{
	register_plugin( "Grab+", VERSION, "Ian Cammarata & NightMira" )
	register_cvar( TRKCVAR, VERSION, FCVAR_SERVER )
	set_cvar_string( TRKCVAR, VERSION )
	
	p_players_only = register_cvar( "gp_players_only", "0" )
	
	p_min_dist = register_cvar ( "gp_min_dist", "90" )
	p_throw_force = register_cvar( "gp_throw_force", "1500" )
	p_grab_force = register_cvar( "gp_grab_force", "8" )
	p_speed = register_cvar( "gp_speed", "5" )
	
	p_choke_time = register_cvar( "gp_choke_time", "1.5" )
	p_choke_dmg = register_cvar( "gp_choke_dmg", "5" )
	p_auto_choke = register_cvar( "gp_auto_choke", "0" )
	
	p_glow_r = register_cvar( "gp_glow_r", "0" )
	p_glow_g = register_cvar( "gp_glow_g", "0" )
	p_glow_b = register_cvar( "gp_glow_b", "0" )
	p_glow_a = register_cvar( "gp_glow_a", "200" )
	
	p_fade = register_cvar( "gp_screen_fade", "0" )
	p_glow = register_cvar( "gp_glow", "1" )
	
	register_clcmd( "amx_grab", "force_grab", _, "Grab client & teleport to you." )
	register_clcmd( "grab_toggle", "grab_toggle", _, "press once to grab and again to release" )
	register_clcmd( "+grab", "grab", _, "bind a key to +grab" )
	/*register_clcmd( "amx_grab", "force_grab", ADMIN, "Grab client & teleport to you." )
	register_clcmd( "grab_toggle", "grab_toggle", ADMIN, "press once to grab and again to release" )
	register_clcmd( "+grab", "grab", ADMIN, "bind a key to +grab" )
	*/
	register_clcmd( "-grab", "unset_grabbed" )
	
	register_clcmd( "+push", "push", _, "bind a key to +push" )
	//register_clcmd( "+push", "push", ADMIN, "bind a key to +push" )
	register_clcmd( "-push", "push" )
	register_clcmd( "+pull", "pull", _, "bind a key to +pull" )
	//register_clcmd( "+pull", "pull", ADMIN, "bind a key to +pull" )
	register_clcmd( "-pull", "pull" )
	
	register_clcmd( "push", "push2" )
	register_clcmd( "pull", "pull2" )
	
	register_clcmd( "drop" ,"throw" )
	
	register_clcmd( "igrab_menu" , "igrab_menu" )
	register_clcmd( "Remove_warn" , "SelectPlayer" )
	/*register_clcmd( "igrab_menu" , "igrab_menu", ADMIN_I )
	register_clcmd( "Remove_warn" , "SelectPlayer", F_WARN_R )
	*/
	
	g_vault = nvault_open( "warns_save" )
	
	register_event( "DeathMsg", "DeathMsg", "a" )
	
	register_forward( FM_PlayerPreThink, "fm_player_prethink" )
	RegisterHam(Ham_Spawn, "player", "Ham_PlayerSpawn_Post", 1);
	
	register_dictionary( "grab_y.txt" )
	
	MAXPLAYERS = get_maxplayers()
	
	SVC_SCREENFADE = get_user_msgid( "ScreenFade" )
	SVC_SCREENSHAKE = get_user_msgid( "ScreenShake" )
	WTF_DAMAGE = get_user_msgid( "Damage" )
}

public plugin_precache()
{
	cheack_file_access();

	precache_model("models/frostnova.mdl");
	
	precache_sound("player/PL_PAIN2.WAV")
	precache_sound("frost/impalehit.wav"); // player is frozen
	precache_sound("frost/impalelaunch1.wav"); // frozen wears off
	
	precache_sound(SND_OFF);
	precache_sound(SND_TASK);
	precache_sound(ON_MENU);
}

public client_PreThink(id){ 
    if(pev( id, pev_button ) & IN_ATTACK) 
    { 
	pull2(id)
    }else if(pev( id, pev_button ) & IN_ATTACK2) 
    { 
	push2(id)
    }
}

public fm_player_prethink( id )
{
	new target
	//Search for a target
	if ( client_data[id][GRABBED] == -1 )
	{
		new Float:orig[3], Float:ret[3]
		get_view_pos( id, orig )
		ret = vel_by_aim( id, 9999 )
		
		ret[0] += orig[0]
		ret[1] += orig[1]
		ret[2] += orig[2]
		
		target = traceline( orig, ret, id, ret )
		
		if( 0 < target <= MAXPLAYERS )
		{
			if( is_grabbed( target, id ) ) return FMRES_IGNORED
			set_grabbed( id, target )
		}
		else if( !get_pcvar_num( p_players_only ) )
		{
			new movetype
			if( target && pev_valid( target ) )
			{
				movetype = pev( target, pev_movetype )
				if( !( movetype == MOVETYPE_WALK || movetype == MOVETYPE_STEP || movetype == MOVETYPE_TOSS ) )
					return FMRES_IGNORED
			}
			else
			{
				target = 0
				new ent = engfunc( EngFunc_FindEntityInSphere, -1, ret, 12.0 )
				while( !target && ent > 0 )
				{
					movetype = pev( ent, pev_movetype )
					if( ( movetype == MOVETYPE_WALK || movetype == MOVETYPE_STEP || movetype == MOVETYPE_TOSS )
							&& ent != id  )
						target = ent
					ent = engfunc( EngFunc_FindEntityInSphere, ent, ret, 12.0 )
				}
			}
			if( target )
			{
				if( is_grabbed( target, id ) ) return FMRES_IGNORED
				set_grabbed( id, target )
			}
		}
	}
	
	target = client_data[id][GRABBED]
	//If they've grabbed something
	if( target > 0 )
	{
		if( !pev_valid( target ) || ( pev( target, pev_health ) < 1 && pev( target, pev_max_health ) ) )
		{
			unset_grabbed( id )
			return FMRES_IGNORED
		}
		 
		//Use key choke
		if( pev( id, pev_button ) & IN_USE )
			do_choke( id )
		
		//Push and pull
		new cdf = client_data[id][FLAGS]
		if ( cdf & CDF_IN_PULL )
			do_pull( id )
		else if ( cdf & CDF_IN_PUSH )
			do_push( id )
		
		if( target > MAXPLAYERS ) grab_think( id )
	}
	
	//If they're grabbed
	target = client_data[id][GRABBER]
	if( target > 0 ) grab_think( target )
	
	return FMRES_IGNORED
}

public grab_think( id ) //id of the grabber
{
	new target = client_data[id][GRABBED]
	
	//Keep grabbed clients from sticking to ladders
	if( pev( target, pev_movetype ) == MOVETYPE_FLY && !(pev( target, pev_button ) & IN_JUMP ) ) client_cmd( target, "+jump;wait;-jump" )
	
	//Move targeted client
	new Float:tmpvec[3], Float:tmpvec2[3], Float:torig[3], Float:tvel[3]
	
	get_view_pos( id, tmpvec )
	
	tmpvec2 = vel_by_aim( id, client_data[id][GRAB_LEN] )
	
	torig = get_target_origin_f( target )
	
	new force = get_pcvar_num( p_grab_force )
	
	tvel[0] = ( ( tmpvec[0] + tmpvec2[0] ) - torig[0] ) * force
	tvel[1] = ( ( tmpvec[1] + tmpvec2[1] ) - torig[1] ) * force
	tvel[2] = ( ( tmpvec[2] + tmpvec2[2] ) - torig[2] ) * force
	
	set_pev( target, pev_velocity, tvel )
}

stock Float:get_target_origin_f( id )
{
	new Float:orig[3]
	pev( id, pev_origin, orig )
	
	//If grabbed is not a player, move origin to center
	if( id > MAXPLAYERS )
	{
		new Float:mins[3], Float:maxs[3]
		pev( id, pev_mins, mins )
		pev( id, pev_maxs, maxs )
		
		if( !mins[2] ) orig[2] += maxs[2] / 2
	}
	
	return orig
}

public grab_toggle( id, level, cid )
{
	if( !client_data[id][GRABBED] ) grab( id, level, cid )
	else unset_grabbed( id )
	
	return PLUGIN_HANDLED
}

public grab(id, level, cid)
{
	if(!get_access(id, eAccess)) return PLUGIN_HANDLED;
	//if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED
	
	if (!client_data[id][GRABBED]) client_data[id][GRABBED] = -1
	screenfade_in(id)

	g_bShowMenu[id] = true;

	return PLUGIN_HANDLED
}
public screenfade_in( id )
{
	if( get_pcvar_num( p_fade ) )
	{
		message_begin( MSG_ONE, SVC_SCREENFADE, _, id )
		write_short( 10000 ) //duration
		write_short( 0 ) //hold
		write_short( SF_FADE_IN + SF_FADE_ONLYONE ) //flags
		write_byte( get_pcvar_num( p_glow_r ) ) //r
		write_byte( get_pcvar_num( p_glow_g ) ) //g
		write_byte( get_pcvar_num( p_glow_b ) ) //b
		write_byte( get_pcvar_num( p_glow_a ) / 2 ) //a
		message_end( )
	}
}


public throw( id )
{
	new target = client_data[id][GRABBED]
	if( target > 0 )
	{
		set_pev( target, pev_velocity, vel_by_aim( id, get_pcvar_num(p_throw_force) ) )
		unset_grabbed( id )
		return PLUGIN_HANDLED
	}

	return PLUGIN_CONTINUE
}

public unset_grabbed( id )
{
	new target = client_data[id][GRABBED]
	if( target > 0 && pev_valid( target ) )
	{
		set_pev( target, pev_renderfx, kRenderFxNone )
		set_pev( target, pev_rendercolor, {255.0, 255.0, 255.0} )
		set_pev( target, pev_rendermode, kRenderNormal )
		set_pev( target, pev_renderamt, 16.0 )
		
		if(is_user_alive(target) && g_Freeze[target])
		{
			set_rendering(target, kRenderFxGlowShell, FROST_R, FROST_G, FROST_B, kRenderNormal, 30);
		}
		
		if( 0 < target <= MAXPLAYERS )
			client_data[target][GRABBER] = 0
	}
	client_data[id][GRABBED] = 0
	
	if( get_pcvar_num( p_fade ) )
	{
		message_begin( MSG_ONE, SVC_SCREENFADE, _, id )
		write_short( 10000 ) //duration
		write_short( 0 ) //hold
		write_short( SF_FADEOUT ) //flags
		write_byte( get_pcvar_num( p_glow_r ) ) //r
		write_byte( get_pcvar_num( p_glow_g ) ) //g
		write_byte( get_pcvar_num( p_glow_b ) ) //b
		write_byte( get_pcvar_num( p_glow_a ) / 2 ) //a
		message_end( )
	}
	
	if(g_bShowMenu[id])				show_menu(id, 0, "^n", 1);
}

//Grabs onto someone
public set_grabbed( id, target )
{
	client_data[id][GRABBED] = target

	if( g_immunity[target] && !get_access(id, eAntiImmunity) )
	//if( g_immunity[target] && !(get_user_flags(id) & ADMIN_GL) )
	{
		client_print_color(id, print_team_default, "%s ^3Нельзя взять, у игрока иммунитет!", szPrefix);
	}else{
		new t_name[32];
		get_user_name(target, t_name, charsmax(t_name))
		if( 0 < target <= MAXPLAYERS )
		client_data[target][GRABBER] = id
		client_data[id][FLAGS] = 0
	
		if( get_pcvar_num( p_glow ) )
		{
			new Float:color[3]
			color[0] = get_pcvar_float( p_glow_r )
			color[1] = get_pcvar_float( p_glow_g )
			color[2] = get_pcvar_float( p_glow_b )
			set_pev( target, pev_renderfx, kRenderFxGlowShell )
			set_pev( target, pev_rendercolor, color )
			set_pev( target, pev_rendermode, kRenderTransColor )
			set_pev( target, pev_renderamt, get_pcvar_float( p_glow_a ) )
		}
	
		new Float:torig[3], Float:orig[3]
		pev( target, pev_origin, torig )
		pev( id, pev_origin, orig )
		client_data[id][GRAB_LEN] = floatround( get_distance_f( torig, orig ) )
		if( client_data[id][GRAB_LEN] < get_pcvar_num( p_min_dist ) ) client_data[id][GRAB_LEN] = get_pcvar_num( p_min_dist )
		
		if(is_user_connected(target))
		{
			if(g_bShowMenu[id]) grab_menu(id)
            
			new name[32]; get_user_name(id, name, charsmax(name))
			client_print_color(target, print_team_default, "%s ^1Вас взял грабом ^3%s", szPrefix, name);
		}
	}
}

public igrab_menu(id) 
{
	if(!get_access(id, eImmunity)) return PLUGIN_HANDLED;
	new Item[512], menu;

	formatex(Item, charsmax(Item), "\y| \r# \y| \wМеню: \y| \rГраба \y|");

	menu = menu_create(Item, "imenu_handler");
		
	if(g_immunity[id]){
		menu_additem(menu, "\wИммунитет: \d[\yВКЛ\d|\rвыкл\d]");
	}else{
		menu_additem(menu, "\wИммунитет: \d[\rвкл\d|\yВЫКЛ\d]");
	}
		
	menu_setprop(menu, MPROP_EXITNAME, "Выход")
	menu_display(id, menu, 0);

	return PLUGIN_HANDLED;
}

public imenu_handler(id, menu, item) 
{
	new name[32];
	get_user_name(id, name, charsmax(name));

	item++;

	switch(item) 
	{
		case 1: {
			client_cmd(id, "spk ^"%s^"", ON_MENU)
			if(!g_immunity[id]){
				g_immunity[id] = true;
			}else{
				g_immunity[id] = false;
			}
			igrab_menu(id)
		}
	}
	return PLUGIN_HANDLED
}

public grab_menu(id) 
{
	new name[32]
	new iTarget = client_data[id][GRABBED]

	if(is_user_alive(iTarget))
	{
		get_user_name(iTarget, name, charsmax(name))

		new Item[512], Item1[512], Item2[512], menu;

		formatex(Item, charsmax(Item), "\y| \r# \y| \wМеню: \y| \rГраба \y|^n\y| \r# \y| \wВы держите: \y%s^n\dЛКМ - отдалить, ПКМ - приблизить", name);
		
		formatex(Item1, charsmax(Item1), "Выдать предупреждение \d(\y%d\d/\y%d\d)", g_warns[iTarget], MAX_WARNS);
		formatex(Item2, charsmax(Item2), "Забрать предупреждение \d(\y%d\d/\y%d\d)^n", g_warns[iTarget], MAX_WARNS);

		menu = menu_create(Item, "menu_handler");
		
		if(get_access(id, eWarn)) menu_additem(menu, Item1);
		//if(get_user_flags(id) & F_WARNS) menu_additem(menu, Item1);
		else menu_additem(menu, "\dВыдать предупреждение");
		
		if(get_access(id, eWarnR)) menu_additem(menu, Item2);
		//if(get_user_flags(id) & F_WARN_R) menu_additem(menu, Item2);
		else menu_additem(menu, "\dЗабрать предупреждение^n");
		
		menu_additem(menu, "Показать правила");

		menu_additem(menu, "Убить");
		
		if(g_Freeze[iTarget])
		{
			menu_additem(menu, "Разморозить");
		}
		else menu_additem(menu, "Заморозить");
		
		if(g_immunity[iTarget]){
			menu_additem(menu, "\wИммунитет: \d[\yВКЛ\d|\rвыкл\d]");
		}else{
			menu_additem(menu, "\wИммунитет: \d[\rвкл\d|\yВЫКЛ\d]");
		}

		menu_setprop(menu, MEXIT_ALL, 0)
		menu_display(id, menu, 0);
	}

	return PLUGIN_HANDLED;
}

public menu_handler(id, menu, item) 
{
	new iTarget = client_data[id][GRABBED]
	
	if(iTarget == 0)		return 1;
	
	new name[32], t_name[32];
	get_user_name(id, name, charsmax(name));
	get_user_name(iTarget, t_name, charsmax(name))

	item++;

	switch(item) 
	{
		case 1: {
			if( get_access(id, eWarn) )
			//if( get_user_flags(id) & F_WARNS )
			{
				client_cmd(id, "spk ^"%s^"", ON_MENU)
				g_warns[iTarget]++
				switch(g_warns[iTarget]){
					case 1: {
						user_kill(iTarget, 1)
						client_print_color(0, print_team_default, "%s ^4%s ^3выдал(а) предупреждение игроку ^4%s ^1(^3%d^1/^3%d^1)", szPrefix, name, t_name, g_warns[iTarget], MAX_WARNS);
					}
					case 2: {
						server_cmd("kick #%d Второе предупреждение (%s)", get_user_userid(iTarget), name)
						client_print_color(0, print_team_default, "%s ^4%s ^3выдал(а) предупреждение игроку ^4%s ^1(^3%d^1/^3%d^1)", szPrefix, name, t_name, g_warns[iTarget], MAX_WARNS);
					}
					case 3:	{
						server_cmd("fb_ban 5 #%d Третье предупреждение (%s)", get_user_userid(iTarget), name)
						client_print_color(0, print_team_default, "%s ^4%s ^3выдал(а) предупреждение игроку ^4%s ^1(^3%d^1/^3%d^1)", szPrefix, name, t_name, g_warns[iTarget], MAX_WARNS);
					}
					case 4: {
						server_cmd("fb_ban 60 #%d Четвертое предупреждение (%s)", get_user_userid(iTarget), name)
						client_print_color(0, print_team_default, "%s ^4%s ^3выдал(а) предупреждение игроку ^4%s ^1(^3%d^1/^3%d^1)", szPrefix, name, t_name, g_warns[iTarget], MAX_WARNS);
					}
					case 5: {
						server_cmd("fb_ban 1440 #%d Пятое предупреждение (%s)", get_user_userid(iTarget), name)
						client_print_color(0, print_team_default, "%s ^4%s ^3выдал(а) предупреждение игроку ^4%s ^1(^3%d^1/^3%d^1)", szPrefix, name, t_name, g_warns[iTarget], MAX_WARNS);
					}
				}
			}else{
				client_cmd(id, "spk ^"%s^"", SND_OFF)
				client_print_color(id, print_team_default, "%s ^3%L", szPrefix, id, "ACCESS");
				return grab_menu(id)
			}
		}
		case 2: {
			if( get_access(id, eWarnR) )
			//if( get_user_flags(id) & F_WARN_R )
			{
				client_cmd(id, "spk ^"%s^"", SND_TASK)
				g_warns[iTarget]--
				client_print_color(0, print_team_default, "%s ^4%s ^3забрал(а) предупреждение у игрока ^4%s", szPrefix, name, t_name);
				return grab_menu(id)
			}else{
				client_cmd(id, "spk ^"%s^"", SND_OFF)
				client_print_color(id, print_team_default, "%s ^3%L", szPrefix, id, "ACCESS");
				return grab_menu(id)
			}
		}
		case 3: {
			client_cmd(id, "spk ^"%s^"", ON_MENU)
			client_cmd(iTarget, "spk ^"%s^"", SND_TASK)
			set_hudmessage(200, 150, 0, 0.05, 0.15, 2, 6.0, 20.0, 0.05, 0.5)
			show_hudmessage(iTarget, "Правила на мосту:^n^n- Не паровозить^n- Не подпирать^n- Не крысить (со спины)^n- Не убивать с парашюта!^n- Не стоять в АФК!^n- Не обходить^n^nОсновные правила:^n^n- Не оскорблять игроков^n- Микрофон строго 16+^n- Не рекламить^n- Не флудить^n- Не спамить")
			client_print_color(0, print_team_default, "%s ^4%s ^3показал(а) правила игроку ^4%s", szPrefix, name, t_name);
			return grab_menu(id)
		}
		case 4: {
			client_cmd(id, "spk ^"%s^"", ON_MENU)
			client_print_color(0, print_team_default, "%s ^4%s ^3убил(а) ^4%s", szPrefix, name, t_name);
			user_kill(iTarget, 1)
		}
		case 5: {
			client_cmd(id, "spk ^"%s^"", ON_MENU)
			if(!is_user_connected(iTarget))
			{
				client_print_color(id, print_team_default, "%s Игрок покинул(а) сервер", szPrefix)
				return PLUGIN_HANDLED;
			}
			
			if(g_Freeze[iTarget])
			{
				unfreeze_player(iTarget);
				client_print_color(0, print_team_default, "%s ^4%s ^3разморозил(а) ^4%s", szPrefix, name, t_name);
			}
			else
			{
				freeze_player(iTarget);
				client_print_color(0, print_team_default, "%s ^4%s ^3заморозил(а) ^4%s", szPrefix, name, t_name);
			}
			return grab_menu(id)
		}
		case 6: {
			client_cmd(id, "spk ^"%s^"", ON_MENU)
			if(!g_immunity[id]){
				g_immunity[id] = true;
			}else{
				g_immunity[id] = false;
			}
			return grab_menu(id)
		}
	}
	return PLUGIN_HANDLED
}

public freeze_player(id)
{
	g_Freeze[id] = true;
	
	set_pev(id, pev_flags, pev(id, pev_flags) | FL_FROZEN);

	emit_sound(id,CHAN_BODY, "frost/impalehit.wav", 1.0, ATTN_NORM, 0, PITCH_HIGH);

	new nova = create_entity("info_target");

	// give it a size
	new Float:maxs[3], Float:mins[3];
	maxs = Float:{ 8.0, 8.0, 4.0 };
	mins = Float:{ -8.0, -8.0, -4.0 };
	entity_set_size(nova,mins,maxs);

	// random orientation
	new Float:angles[3];
	angles[1] = float(random_num(0,359));
	entity_set_vector(nova,EV_VEC_angles,angles);

	// put it at their feet
	new Float:playerMins[3], Float:novaOrigin[3];
	entity_get_vector(id,EV_VEC_mins,playerMins);
	entity_get_vector(id,EV_VEC_origin,novaOrigin);

	novaOrigin[2] += playerMins[2];
	entity_set_vector(nova,EV_VEC_origin,novaOrigin);

	// mess with the model
	entity_set_model(nova,"models/frostnova.mdl");
	entity_set_float(nova,EV_FL_animtime,1.0)
	entity_set_float(nova,EV_FL_framerate,1.0)
	entity_set_int(nova,EV_INT_sequence,0);
	set_pev(nova, pev_classname, CLASSNAME)
	set_pev(nova, pev_owner, id)

	set_rendering(nova,kRenderFxNone,FROST_R, FROST_G, FROST_B,kRenderTransColor,100);
	set_rendering(id, kRenderFxGlowShell, FROST_R, FROST_G, FROST_B, kRenderNormal, 30);
}

public unfreeze_player(id)
{
	g_Freeze[id] = false;

	set_pev(id, pev_flags, pev(id, pev_flags) & ~FL_FROZEN);
	set_pev(id, pev_renderfx, kRenderFxNone)

	emit_sound(id,CHAN_BODY, "frost/impalelaunch1.wav", 1.0, ATTN_NORM, 0, PITCH_HIGH);
	
	new nova = find_ent_by_owner(0, CLASSNAME, id)
	
	if(!pev_valid(nova)) return
	
	remove_entity(nova);
}

public Ham_PlayerSpawn_Post(id)
{
	if(is_user_alive(id))
	{
		g_Freeze[id] = false
	}
	
	new nova = find_ent_by_owner(0, CLASSNAME, id)
	
	if(!pev_valid(nova)) return
	
	remove_entity(nova);
}

public push( id )
{
	client_data[id][FLAGS] ^= CDF_IN_PUSH
	return PLUGIN_HANDLED
}

public pull( id )
{
	client_data[id][FLAGS] ^= CDF_IN_PULL
	return PLUGIN_HANDLED
}

public push2( id )
{
	if( client_data[id][GRABBED] > 0 )
	{
		do_push( id )
		return PLUGIN_HANDLED
	}
	return PLUGIN_CONTINUE
}

public pull2( id )
{
	if( client_data[id][GRABBED] > 0 )
	{
		do_pull( id )
		return PLUGIN_HANDLED
	}
	return PLUGIN_CONTINUE
}

public do_push( id )
	if( client_data[id][GRAB_LEN] < 9999 )
		client_data[id][GRAB_LEN] += get_pcvar_num( p_speed )

public do_pull( id )
{
	new mindist = get_pcvar_num( p_min_dist )
	new len = client_data[id][GRAB_LEN]
	
	if( len > mindist )
	{
		len -= get_pcvar_num( p_speed )
		if( len < mindist ) len = mindist
		client_data[id][GRAB_LEN] = len
	}
	else if( get_pcvar_num( p_auto_choke ) )
		do_choke( id )
}

public do_choke( id )
{
	new target = client_data[id][GRABBED]
	if( client_data[id][FLAGS] & CDF_NO_CHOKE || id == target || target > MAXPLAYERS) return
	
	new dmg = get_pcvar_num( p_choke_dmg )
	new vec[3]
	FVecIVec( get_target_origin_f( target ), vec )
	
	message_begin( MSG_ONE, SVC_SCREENSHAKE, _, target )
	write_short( 999999 ) //amount
	write_short( 9999 ) //duration
	write_short( 999 ) //frequency
	message_end( )
	
	message_begin( MSG_ONE, SVC_SCREENFADE, _, target )
	write_short( 9999 ) //duration
	write_short( 100 ) //hold
	write_short( SF_FADE_MODULATE ) //flags
	write_byte( get_pcvar_num( p_glow_r ) ) //r
	write_byte( get_pcvar_num( p_glow_g ) ) //g
	write_byte( get_pcvar_num( p_glow_b ) ) //b
	write_byte( 200 ) //a
	message_end( )
	
	message_begin( MSG_ONE, WTF_DAMAGE, _, target )
	write_byte( 0 ) //damage armor
	write_byte( dmg ) //damage health
	write_long( DMG_CRUSH ) //damage type
	write_coord( vec[0] ) //origin[x]
	write_coord( vec[1] ) //origin[y]
	write_coord( vec[2] ) //origin[z]
	message_end( )
		
	message_begin( MSG_BROADCAST, SVC_TEMPENTITY )
	write_byte( TE_BLOODSTREAM )
	write_coord( vec[0] ) //pos.x
	write_coord( vec[1] ) //pos.y
	write_coord( vec[2] + 15 ) //pos.z
	write_coord( random_num( 0, 255 ) ) //vec.x
	write_coord( random_num( 0, 255 ) ) //vec.y
	write_coord( random_num( 0, 255 ) ) //vec.z
	write_byte( 70 ) //col index
	write_byte( random_num( 50, 250 ) ) //speed
	message_end( )
	
	//Thanks to ConnorMcLeod for making this block of code more proper
	new Float:health
	pev( target, pev_health , health)
	health -= dmg 
	if( health < 1 ) dllfunc( DLLFunc_ClientKill, target )
	else {
		set_pev( target, pev_health, health )
		set_pdata_int(target, m_bitsDamageType, DMG_CRUSH) // m_bitsDamageType = 76 // found by VEN
		set_pev(target, pev_dmg_take, dmg)
		set_pev(target, pev_dmg_inflictor, id)
	}
	
	client_data[id][FLAGS] ^= CDF_NO_CHOKE
	set_task( get_pcvar_float( p_choke_time ), "clear_no_choke", TSK_CHKE + id )
}

public clear_no_choke( tskid )
{
	new id = tskid - TSK_CHKE
	client_data[id][FLAGS] ^= CDF_NO_CHOKE
}

//Grabs the client and teleports them to the admin
public force_grab(id, level, cid)
{
	if(!get_access(id, eAccess)) return PLUGIN_HANDLED;
	//if(!cmd_access(id, level, cid, 1)) return PLUGIN_HANDLED

	new arg[33]
	read_argv(1, arg, 32)

	new targetid = cmd_target(id, arg, 1)
	
	if(is_grabbed(targetid, id)) return PLUGIN_HANDLED
	if(!is_user_alive(targetid))
	{
		client_print(id, print_console, "[AMXX] %L", id, "COULDNT")
		return PLUGIN_HANDLED
	}
	
	//Safe to tp target to aim spot?
	new Float:tmpvec[3], Float:orig[3], Float:torig[3], Float:trace_ret[3]
	new bool:safe = false, i
	
	get_view_pos(id, orig)
	tmpvec = vel_by_aim(id, GRAB_MIN_DIST)
	
	for(new j = 1; j < 11 && !safe; j++)
	{
		torig[0] = orig[0] + tmpvec[i] * j
		torig[1] = orig[1] + tmpvec[i] * j
		torig[2] = orig[2] + tmpvec[i] * j
		
		traceline(tmpvec, torig, id, trace_ret)
		
		if(get_distance_f(trace_ret, torig)) break
		
		engfunc(EngFunc_TraceHull, torig, torig, 0, HULL_HUMAN, 0, 0)
		if (!get_tr2(0, TR_StartSolid) && !get_tr2(0, TR_AllSolid) && get_tr2(0, TR_InOpen))
			safe = true
	}
	
	//Still not safe? Then find another safe spot somewhere around the grabber
	pev(id, pev_origin, orig)
	new try[3]
	orig[2] += 2
	while(try[2] < 3 && !safe)
	{
		for(i = 0; i < 3; i++)
			switch(try[i])
			{
				case 0 : torig[i] = orig[i] + (i == 2 ? 80 : 40)
				case 1 : torig[i] = orig[i]
				case 2 : torig[i] = orig[i] - (i == 2 ? 80 : 40)
			}
		
		traceline(tmpvec, torig, id, trace_ret)
		
		engfunc(EngFunc_TraceHull, torig, torig, 0, HULL_HUMAN, 0, 0)
		if (!get_tr2(0, TR_StartSolid) && !get_tr2(0, TR_AllSolid) && get_tr2(0, TR_InOpen)
				&& !get_distance_f(trace_ret, torig)) safe = true
		
		try[0]++
		if(try[0] == 3)
		{
			try[0] = 0
			try[1]++
			if(try[1] == 3)
			{
				try[1] = 0
				try[2]++
			}
		}
	}
	
	if(safe)
	{
		set_pev(targetid, pev_origin, torig)
		set_grabbed(id, targetid)
		screenfade_in(id)	
	}
	else client_print(id, print_chat, "[AMXX] %L", id, "COULDNT")

	return PLUGIN_HANDLED
}

public is_grabbed( target, grabber )
{
	for( new i = 1; i <= MAXPLAYERS; i++ )
		if( client_data[i][GRABBED] == target )
		{
			client_print( grabber, print_chat, "[AMXX] %L", grabber, "ALREADY" )
			unset_grabbed( grabber )
			return true
		}
	return false
}

public DeathMsg( )
	kill_grab( read_data( 2 ) )
	
public client_putinserver(id)
{
	LoadDataWarns(id)
	if(g_warns[id] == MAX_WARNS) g_warns[id] = 0;
	cheack_access(id);

	if(get_access(id, eImmunity)) g_immunity[id] = true;
	//if(get_user_flags(id) & ADMIN_I) g_immunity[id] = true;
	
	return PLUGIN_CONTINUE
}

public client_disconnected(id)
{
	kill_grab(id)
	g_Freeze[id] = false
	
	SaveDataWarns(id)
	g_warns[id] = 0
	
	g_immunity[id] = false;
	
	new nova = find_ent_by_owner(0, CLASSNAME, id)
	
	if(!pev_valid(nova)) return 1;
	
	remove_entity(nova);
	
	return PLUGIN_CONTINUE
}

public plugin_end() nvault_close(g_vault)

public SaveDataWarns( id ) {
	new AuthID[ 35 ]
	get_user_authid( id, AuthID, 34 )
	
	new vaultkey [64 ], vaultdata[ 256 ]
	format( vaultkey, 63, "%s-cso", AuthID )
	format( vaultdata, 255, "%i#", g_warns[ id ] )
	nvault_set( g_vault, vaultkey, vaultdata )
	
	return PLUGIN_CONTINUE
}

public LoadDataWarns( id ) {
	new AuthID[ 35 ]
	get_user_authid( id, AuthID, 34 )
	
	new vaultkey[ 64 ], vaultdata[ 256 ]
	format( vaultkey, 63, "%s-cso", AuthID )
	format( vaultdata, 255, "%i#", g_warns[ id ] )
	nvault_get( g_vault, vaultkey, vaultdata, 255 )
	
	replace_all( vaultdata, 255, "#", " " )
	
	new warns[ 32 ]
	
	parse( vaultdata, warns, 31 )
	
	g_warns[ id ] = str_to_num( warns )
	
	return PLUGIN_CONTINUE
}

public kill_grab( id )
{
	//If given client has grabbed, or has a grabber, unset it
	if( client_data[id][GRABBED] )
		unset_grabbed( id )
	else if( client_data[id][GRABBER] )
		unset_grabbed( client_data[id][GRABBER] )
}

public SelectPlayer(iPlayer){
	if(!get_access(iPlayer, eWarnR)) return PLUGIN_HANDLED;
	new Players[32], Players_num
	get_players(Players, Players_num, "ch") 
	new players_warns=0;
	
	for(new i=1; i <= Players_num; i++){
		if(g_warns[i] != 0){
			if(Players[i] == iPlayer){
				continue;
			}else{
				players_warns++;
			}
		}
	}
	
	if(players_warns == 0) 
	{
		client_cmd(iPlayer, "spk ^"%s^"", SND_OFF)
		client_print_color(iPlayer, print_team_default, "^1[^4%L^1] ^3Нет игроков с предупреждениями!", LANG_PLAYER, "PREFIX");
		return PLUGIN_HANDLED;
	}	
	
	new mc_SP = menu_create("\y| \r# \y| \wВыберите игрока \y|", "Handler_SP")
	new szItem[64], nickname[33]	
	if(players_warns != 0){
		for(new i=1; i <= players_warns; i++){
			get_user_name(Players[i], nickname, charsmax(nickname));
			
			formatex(szItem, charsmax(szItem), "%s \d[\y%d\d]", nickname, g_warns[i]);
			menu_additem(mc_SP, szItem, nickname);
		}
	}
	
	menu_setprop(mc_SP, MPROP_NEXTNAME, "Далее")
   	menu_setprop(mc_SP, MPROP_BACKNAME, "Назад")
	menu_setprop(mc_SP, MPROP_EXITNAME, "Выход")
	
	menu_display(iPlayer, mc_SP, 0);
	return PLUGIN_HANDLED;
}
public Handler_SP(id, menu, item){
	if(item == MENU_EXIT)     
	{     
		menu_destroy(menu)
	}
	
	new s_Data[30], s_Name[64], i_Access, i_Callback, iPlayer
	menu_item_getinfo(menu, item, i_Access, s_Data, charsmax(s_Data), s_Name, charsmax(s_Name), i_Callback)
	
	new nickname[33]
	get_user_name(id, nickname, charsmax(nickname))
	iPlayer = get_user_index(s_Data)
	
	g_warns[iPlayer]--
	client_cmd(id, "spk ^"%s^"", SND_TASK)
	client_print_color(0, print_team_default, "^1[^4%L^1] ^4%s ^3забрал предупреждение у ^4%s", LANG_PLAYER, "PREFIX", nickname, s_Data);
	
	menu_destroy(menu);
}



new const PATH_DIR[] = "GrabAccess";
new const FILE_ACCESS[] = "user.ini";

new Array:g_aAccess;
new g_aPlayerData[MAX_PLAYERS + 1][eFlagsAccess - 1];

public cheack_file_access() {
	g_aAccess = ArrayCreate(eFlagsAccess, 0);
	new sPath[MAX_RESOURCE_PATH_LENGTH];
	
	new aAccessData[eFlagsAccess];

	get_localinfo("amxx_configsdir", sPath, charsmax(sPath));
	formatex(sPath, charsmax(sPath), "%s/%s", sPath, PATH_DIR);

	if(!dir_exists(sPath))
		mkdir(sPath);

	formatex(sPath, charsmax(sPath), "%s/%s", sPath, FILE_ACCESS);

	if(file_exists(sPath)) {
		new hFile = fopen(sPath, "rt");
		if(hFile) {
			new iLine = 0;
			new sBuffer[128];
			new sNameData[MAX_NAME_LENGTH];
			new sFlagAccess[1];
			new sFlagImmunity[1];
			new sFlagantiImmunity[1];
			new sFlagWarn[1];
			new sFlagWarnR[1];

			while(!feof(hFile)) {
				iLine++;
				fgets(hFile, sBuffer, charsmax(sBuffer));
				trim(sBuffer);

				if(sBuffer[0] == EOS || sBuffer[0] == ';') continue;
				
				if(parse(sBuffer, 
						sNameData, charsmax(sNameData),
						sFlagAccess, charsmax(sFlagAccess),
						sFlagImmunity, charsmax(sFlagImmunity),
						sFlagantiImmunity, charsmax(sFlagantiImmunity),
						sFlagWarn, charsmax(sFlagWarn),
						sFlagWarnR, charsmax(sFlagWarnR)
					) == 6) {
					aAccessData[eName] = sNameData;
					aAccessData[eAccess] = str_to_num(sFlagAccess);
					aAccessData[eImmunity] = str_to_num(sFlagImmunity);
					aAccessData[eAntiImmunity] = str_to_num(sFlagantiImmunity);
					aAccessData[eWarn] = str_to_num(sFlagWarn);
					aAccessData[eWarn] = str_to_num(sFlagWarnR);
					ArrayPushArray(g_aAccess, aAccessData);
				}
				else {
					log_amx("[ERROR] <user.ini> line %i", iLine);
				}
			}
		}
	}
	else {
		set_fail_state("[GrabAccess] File '%s' not found!", sPath);
	}
	new i = ArraySize(g_aAccess);
	server_print("[GrabAccess] Load %d Grab Admin", i);
}

public cheack_access(iPlayer) {
	new sName[MAX_NAME_LENGTH];
	new aFlags[eFlagsAccess];
	get_user_name(iPlayer, sName, charsmax(sName));

	for(new i = 0; i < ArraySize(g_aAccess); i++) {
		ArrayGetArray(g_aAccess, i, aFlags);
		if(equal(aFlags[eName], sName)) {
			for(new a = 0; a < eFlagsAccess - 1; a++) {
				set_access(iPlayer, a, aFlags[a]);
			}
		}
	}
}

public get_access(iPlayer, iFlag) {
	return g_aPlayerData[iPlayer][iFlag];
}

public set_access(iPlayer, iFlag, iValue) {
	g_aPlayerData[iPlayer][iFlag] = iValue;
}

stock traceline( const Float:vStart[3], const Float:vEnd[3], const pIgnore, Float:vHitPos[3] )
{
	engfunc( EngFunc_TraceLine, vStart, vEnd, 0, pIgnore, 0 )
	get_tr2( 0, TR_vecEndPos, vHitPos )
	return get_tr2( 0, TR_pHit )
}

stock get_view_pos( const id, Float:vViewPos[3] )
{
	new Float:vOfs[3]
	pev( id, pev_origin, vViewPos )
	pev( id, pev_view_ofs, vOfs )		
	
	vViewPos[0] += vOfs[0]
	vViewPos[1] += vOfs[1]
	vViewPos[2] += vOfs[2]
}

stock Float:vel_by_aim( id, speed = 1 )
{
	new Float:v1[3], Float:vBlah[3]
	pev( id, pev_v_angle, v1 )
	engfunc( EngFunc_AngleVectors, v1, v1, vBlah, vBlah )
	
	v1[0] *= speed
	v1[1] *= speed
	v1[2] *= speed
	
	return v1
}