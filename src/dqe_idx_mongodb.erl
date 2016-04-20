%%%-------------------------------------------------------------------
%%% @author Tomasz Szarstuk <szarsti@gmail.com>
%%% @copyright (C) 2016, Dataloop.IO
%%% @doc
%%%
%%% @end
%%%-------------------------------------------------------------------
-module(dqe_idx_mongodb).

-behaviour(dqe_idx).
-behaviour(gen_server).
-behaviour(poolboy_worker).

%% API
-export([start_link/1]).

%% dqe_idx callbacks
-export([expand/2, init/0, lookup/1, add/4, add/5, add/7, delete/4, delete/5,
         delete/7]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2,
         terminate/2, code_change/3]).

-define(POOL, dqe_idx_mongodb_pool).
-define(TIMEOUT, 30000).
-record(state, {connection}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).

%%%===================================================================
%%% dqe_idx callbacks
%%%===================================================================

init() ->
    %% We do not need to initialize anything here.
    ok.

%% It will be running MongoDB queries like:
%%
%%     var mids = db.metricsources.find(
%%         {source: "58078e16-f431-4b05-8836-2191112c5dd5"}, {metric: 1}
%%     ).map(function(ms) {return ms.metric});
%%     db.metrics.find({
%%         _id: {$in: mids},
%%          name: {$regex: /^gauges\.production\.docker\.haproxy\.5555\./}
%%     });
expand(Bucket, Globs) ->
    call({list, Bucket, Globs}).

lookup({'in', B, M}) ->
    {ok, [{B, dproto:metric_from_list(M)}]};

lookup({'in', B, M, _Where}) ->
    {ok, [{B, dproto:metric_from_list(M)}]}.

add(_, _, _, _) ->
    {ok, 0}.

add(_, _, _, _, _) ->
    {ok, 0}.

add(_, _, _, _, _, _, _) ->
    {ok, 0}.

delete(_, _, _, _) ->
    ok.

delete(_, _, _, _, _) ->
    ok.

delete(_, _, _, _, _, _, _) ->
    ok.

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

init(ConnectionArgs) ->
    {ok, C} = mc_worker_api:connect(ConnectionArgs),
    {ok, #state{connection = C}, 0}.

handle_call({list, Bkt, Globs}, _From, #state{connection = C} = State) ->
    Ps1 = lists:map(fun glob_prefix/1, Globs),
    Ps2 = compress_prefixes(Ps1),
    Ms1 = [list_metrics(C, P) || P <- Ps2],
    Ms2 = lists:usort(lists:flatten(Ms1)),
    {reply, {ok, {Bkt, Ms2}}, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State ) ->
    {noreply, State}.

terminate(_Reason, #state{connection = C}) ->
    _ = mc_worker_api:disconnect(C),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

call(Request) ->
    poolboy:transaction(?POOL,
                        fun(S) ->
                                gen_server:call(S, Request, ?TIMEOUT)
                        end, ?TIMEOUT).

list_metrics(C, Prefix) ->
    PParts = dproto:metric_to_list(Prefix),
    [Finger | Path] = PParts,
    #{<<"org">> := Org} =
        mc_worker_api:find_one(C, <<"agents">>, {<<"_id">>, Finger},
                               #{projector => {<<"org">>, true}}),
    NamePattern = binary_join(Path, <<"\.">>),
    NameQuery = {<<"$regex">>, <<"^", NamePattern/binary>>},
    MSCursor = mc_worker_api:find(C, <<"metricsources">>,
                                  {<<"source">>, Finger},
                                 #{projector => {<<"metric">>, true}}),
    MCursor = mc_worker_api:find(C, <<"metrics">>,
                                 {<<"org">>, Org, <<"name">>, NameQuery},
                                 #{projector =>
                                       {<<"_id">>, true, <<"name">>, true}}),
    ValidIdMap = mc_cursor:foldl(
                   fun (#{<<"metric">> := M}, Acc) ->
                           maps:put(M, true, Acc)
                   end, #{}, MSCursor, infinity),
    mc_cursor:close(MSCursor),
    Ms = mc_cursor:foldl(
           fun (#{<<"_id">> := Id, <<"name">> := N}, Acc) ->
                   case maps:is_key(Id, ValidIdMap) of
                       true -> [metric_from_name(Finger, N) | Acc];
                       _ -> Acc
                   end
           end, [], MCursor, infinity),
    mc_cursor:close(MCursor),
    Ms.

binary_join(List, Separator) ->
    lists:foldr(
      fun(A, B) ->
              case B of
                  <<>> -> A;
                  _ -><<A/binary, Separator/binary, B/binary>>
              end
      end, <<>>, List).

metric_from_name(Finger, Name) ->
    Parts = binary:split(Name, <<".">>, [global]),
    dproto:metric_from_list([Finger | Parts]).

%% Stuff below is based on dqe_idx_ddb
glob_prefix(G) ->
    glob_prefix(G, []).

glob_prefix([], Prefix) ->
    dproto:metric_from_list(lists:reverse(Prefix));
glob_prefix(['*' |_], Prefix) ->
    dproto:metric_from_list(lists:reverse(Prefix));
glob_prefix([E | R], Prefix) ->
    glob_prefix(R, [E | Prefix]).

compress_prefixes(Prefixes) ->
    compress_prefixes(lists:sort(Prefixes), []).

compress_prefixes([<<>> | _], _) ->
    all;
compress_prefixes([], R) ->
    R;
compress_prefixes([E], R) ->
    [E | R];
compress_prefixes([A, B | R], Acc) ->
    case binary:longest_common_prefix([A, B]) of
        L when L == byte_size(A) ->
            compress_prefixes([B | R], Acc);
        _ ->
            compress_prefixes([B | R], [A | Acc])
    end.
