%%%-------------------------------------------------------------------
%%% @author Alexander Hudich (alttagil@gmail.com)
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(mongoc).
-author("alttagil").

-include("mongo_protocol.hrl").

-export([connect/3, disconnect/1, command/2, command/3, insert/3, update/4, delete/3, delete_one/3, find_one/3, find_one/4, find/4, find/3, count/3, count/4, count/5, ensure_index/3]).


-type colldb() :: collection() | { database(), collection() }.
-type collection() :: binary() | atom(). % without db prefix
-type database() :: binary() | atom().
-type selector() :: bson:document().
-type cursor() :: pid().
-type write_mode() :: unsafe | safe | {safe, bson:document()}.

-type readmode() :: primary | secondary | primaryPreferred | secondaryPreferred | nearest.
-type host() :: list().
-type seed() :: host()
| { rs, binary(), [host()] }
| { single, host() }
| { unknown, [host()] }
| { sharded, [host()] }.
-type connectoptions() :: [coption()].
-type coption() :: {name, atom()}
|{minPoolSize, integer()}
|{maxPoolSize, integer()}
|{localThresholdMS,integer()}
|{connectTimeoutMS,integer()}
|{socketTimeoutMS,integer()}
|{serverSelectionTimeoutMS,integer()}
|{waitQueueTimeoutMS,integer()}
|{rp_mode,readmode()}
|{rp_tags,list() }.
-type workeroptions() :: [woption()].
-type woption() :: {database, database()}
| {login, binary()}
| {password, binary()}
| {w_mode, write_mode()}.
-type readprefs() :: [readpref()].
-type readpref() :: {rp_mode, readmode()}
|{rp_tags, [tuple()]}.


-spec connect(seed(), connectoptions(), workeroptions()) -> {ok, Pid :: pid()} | ignore | {error, Reason :: term()}.
-spec disconnect(pid()) -> ok.
-spec insert(pid(), colldb(), A) -> A | { error, not_master }.
-spec update(pid(), colldb(), selector(), bson:document()) -> ok | { error, not_master }.
-spec delete(pid(), colldb(), selector()) -> ok | { error, not_master }.
-spec delete_one(pid(), colldb(), selector()) -> ok | { error, not_master }.
-spec find_one(pid(), colldb(), selector()) -> {} | {bson:document()}.
-spec find_one(pid(), colldb(), selector(), readprefs()) -> {} | {bson:document()}.
-spec find(pid(), colldb(), selector()) -> cursor().
-spec find(pid(), colldb(), selector(), readprefs()) -> cursor().
-spec count(pid(), colldb(), selector()) -> integer().
-spec count(pid(), colldb(), selector(), readprefs()) -> integer().
-spec count(pid(), colldb(), selector(), readprefs(), integer()) -> integer().
-spec ensure_index(pid(), colldb(), bson:document()) -> ok | { error, not_master }.
-spec command(pid(), bson:document()) -> {boolean(), bson:document()} | { error, not_master }. % Action
-spec command(pid(), bson:document(), readprefs()) -> {boolean(), bson:document()} | { error, not_master }. % Action


% mongoc:connect( stat,

%					"localhost:27017",
%					{ single, "localhost:27017" },
%					{ rs, <<"rs0">>, [ "localhost:27017", "localhost:27018"] }
%					{ unknown, [ "localhost:27017", "localhost:27018"] }
%					{ sharded, [ "localhost:27017", "localhost:27018"] }

%						[
%							{ name,  mongo1 },

%							{ minPoolSize, 5 },
%							{ maxPoolSize, 10 },

%							{ localThresholdMS, 1000 },

%							{ connectTimeoutMS, 20000 },
%							{ socketTimeoutMS, 100 },

%							{ rp_mode, primary },
%							{ rp_tags, [{tag,1}] },

%							{ serverSelectionTimeoutMS, 30000 },
%							{ waitQueueTimeoutMS, 1000 },
%						]

%						[
%							{login, binary()}
%							{password, binary()}
%							{database, binary()}
%							{w_mode, write_mode()}
%						],

%			).

connect( Seeds, Options, WorkerOptions ) ->
	mc_topology:start_link( Seeds, Options, WorkerOptions ).


disconnect( Topology ) ->
	mc_topology:disconnect( Topology ).




insert( Topology, Coll, Doc ) when is_tuple(Doc); is_map(Doc) ->
	{ ok, #{ pool := C } } = mc_topology:get_pool( Topology, [{rp_mode, primary}] ),
	try	mongo:insert( C, Coll, Doc ) of
		R -> R
	catch
	    error:not_master ->
			mc_topology:update_topology( Topology ),
			{ error, not_master };
		error:{bad_query,{not_master,_}}  ->
			mc_topology:update_topology( Topology ),
			{ error, not_master }
	end.


update( Topology, Coll, Selector, Doc) ->
	{ ok, #{ pool := C } } = mc_topology:get_pool( Topology, [{rp_mode, primary}] ),
	try	mongo:update( C, Coll, Selector, Doc ) of
		R -> R
	catch
		error:not_master ->
			mc_topology:update_topology( Topology ),
			{ error, not_master };
		error:{bad_query,{not_master,_}}  ->
			mc_topology:update_topology( Topology ),
			{ error, not_master }
	end.




delete(Topology, Coll, Selector) ->
	{ ok, #{ pool := C } } = mc_topology:get_pool( Topology, [{rp_mode, primary}] ),
	try	mongo:delete( C, Coll, Selector ) of
		R -> R
	catch
		error:not_master ->
			mc_topology:update_topology( Topology ),
			{ error, not_master };
		error:{bad_query,{not_master,_}}  ->
			mc_topology:update_topology( Topology ),
			{ error, not_master }
	end.



delete_one(Topology, Coll, Selector) ->
	{ ok, #{ pool := C } } = mc_topology:get_pool( Topology, [{rp_mode, primary}] ),
	try	mongo:delete_one( C, Coll, Selector ) of
		R -> R
	catch
		error:not_master ->
			mc_topology:update_topology( Topology ),
			{ error, not_master };
		error:{bad_query,{not_master,_}}  ->
			mc_topology:update_topology( Topology ),
			{ error, not_master }
	end.




find_one(Topology, Coll, Selector) ->
	find_one(Topology, Coll, Selector, []).

find_one(Topology, Coll, Selector, Options) ->
	{ ok, #{ pool := C, server_type := Type, readPreference := RPrefs } } = mc_topology:get_pool( Topology, Options ),
	Projector = mc_utils:get_value(projector, Options, []),
	Skip = mc_utils:get_value(skip, Options, 0),
	Q = #'query'{
		collection = Coll,
		selector = Selector,
		projector = Projector,
		skip = Skip
	},
	mc_action_man:read_one(C, mongos_query_transform( Type, Q, RPrefs ) ).




find(Topology, Coll, Selector) ->
	find(Topology, Coll, Selector, []).

find(Topology, Coll, Selector, Options) ->
	{ ok, #{ pool := C, server_type := Type, readPreference := RPrefs } } = mc_topology:get_pool( Topology, Options ),
	Projector = mc_utils:get_value(projector, Options, []),
	Skip = mc_utils:get_value(skip, Options, 0),
	BatchSize = mc_utils:get_value(batchsize, Options, 0),
	Q = #'query'{
		collection = Coll,
		selector = Selector,
		projector = Projector,
		skip = Skip,
		batchsize = BatchSize
	},
	mc_action_man:read(C, mongos_query_transform( Type, Q, RPrefs ) ).




count( Topology, Coll, Selector ) ->
	count(Topology, Coll, Selector, [], 0).

count( Topology, Coll, Selector, Options ) ->
	count(Topology, Coll, Selector, Options, 0).

count( Topology, Coll, Selector, Options, Limit ) when not is_binary(Coll) ->
	count(Topology, mc_utils:value_to_binary(Coll), Selector, Options, Limit);
count( Topology, Coll, Selector, Options, Limit ) when Limit =< 0 ->
	{true, #{<<"n">> := N}} = command(Topology, {<<"count">>, Coll, <<"query">>, Selector}, Options),
	trunc(N);
count( Topology, Coll, Selector, Options, Limit ) ->
	{true, #{<<"n">> := N}} = command(Topology, {<<"count">>, Coll, <<"query">>, Selector, <<"limit">>, Limit}, Options ),
	trunc(N). % Server returns count as float




ensure_index( Topology, Coll, IndexSpec ) ->
	{ ok, #{ pool := C } } = mc_topology:get_pool( Topology, [{rp_mode, primary}] ),
	try	mc_connection_man:request_async(C, #ensure_index{collection = Coll, index_spec = IndexSpec}) of
		R -> R
	catch
		error:not_master ->
			mc_topology:update_topology( Topology ),
			{ error, not_master };
		error:{bad_query,{not_master,_}}  ->
			mc_topology:update_topology( Topology ),
			{ error, not_master }
	end.




command( Topology, Command ) ->
	command( Topology, Command, [] ).

command( Topology, Command, Options ) ->
	{ ok, #{ pool := C, server_type := Type, readPreference := RPrefs } } = mc_topology:get_pool( Topology, Options ),
	Q = #'query'{
		collection = <<"$cmd">>,
		selector = Command
	},

	try	exec_command( C, mongos_query_transform( Type, Q, RPrefs ) ) of
		R -> R
	catch
		error:not_master ->
			mc_topology:update_topology( Topology ),
			{ error, not_master };
		error:{bad_query,{not_master,_}}  ->
			mc_topology:update_topology( Topology ),
			{ error, not_master }
	end.

% @private
exec_command( C, Command ) ->
	Doc = mc_action_man:read_one( C, Command ),
	mc_connection_man:process_reply( Doc, Command ).




%%%===================================================================
%%% Internal functions
%%%===================================================================

%% @private

mongos_query_transform( mongos, #'query'{ selector = S } = Q, #{ mode := primary } ) ->
	Q#'query'{ selector = S, slaveok = false, sok_overriden = true };

mongos_query_transform( mongos, #'query'{ selector = S } = Q, #{ mode := secondary, tags := Tags } ) ->
	Q#'query'{ selector = bson:document( [ { '$query', S }, { '$readPreference', [ { mode, secondary }, {tags,Tags} ] } ] ), slaveok = true, sok_overriden = true };

mongos_query_transform( mongos, #'query'{ selector = S } = Q, #{ mode := primaryPreferred, tags := [] } ) ->
	Q#'query'{ selector = S, slaveok = true, sok_overriden = true };

mongos_query_transform( mongos, #'query'{ selector = S } = Q, #{ mode := primaryPreferred, tags := Tags } ) ->
	Q#'query'{ selector = bson:document( [ { '$query', S }, { '$readPreference', [ { mode, secondary }, {tags,Tags} ] } ] ), slaveok = true, sok_overriden = true };

mongos_query_transform( mongos, #'query'{ selector = S } = Q, #{ mode := primaryPreffered, tags := Tags } ) ->
	Q#'query'{ selector = bson:document( [ { '$query', S }, { '$readPreference', [ { mode, primaryPreffered }, {tags,Tags} ] } ] ), slaveok = true, sok_overriden = true };

mongos_query_transform( mongos, #'query'{ selector = S } = Q, #{ mode := nearest, tags := Tags } ) ->
	Q#'query'{ selector = bson:document( [ { '$query', S }, { '$readPreference', [ { mode, nearest }, {tags,Tags} ] } ] ), slaveok = true, sok_overriden = true };

% for test purposes only ->
% mongos_query_transform( rsSecondary, #'query'{ selector = S } = Q, #{ mode := secondary, tags := Tags } ) ->
%	Q#'query'{ selector = bson:document( [ { '$query', S }, { '$readPreference', [ { mode, secondary }, {tags,Tags} ] } ] ), slaveok = true, sok_overriden = true };

mongos_query_transform( _, Q, #{ mode := primary } ) ->
	Q#'query'{ slaveok = false, sok_overriden = true };

mongos_query_transform( _, Q, _ ) ->
	Q#'query'{ slaveok = true, sok_overriden = true }.
