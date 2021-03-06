%% -*- erlang-indent-level: 4; indent-tabs-mode: nil; fill-column: 80 -*-
%%% Copyright 2012 Erlware, LLC. All Rights Reserved.
%%%
%%% This file is provided to you under the Apache License,
%%% Version 2.0 (the "License"); you may not use this file
%%% except in compliance with the License.  You may obtain
%%% a copy of the License at
%%%
%%%   http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing,
%%% software distributed under the License is distributed on an
%%% "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
%%% KIND, either express or implied.  See the License for the
%%% specific language governing permissions and limitations
%%% under the License.
%%%---------------------------------------------------------------------------
%%% @author Erlware <core@erlware.org>
%%% @copyright (C) 2013 Erlware, LLC.
%%%
%%% @doc
%%%  Erlang interface for Heroku's PostgreSQL
%%% @end
-module(dikdik_sup).

-behaviour(supervisor).

%% API
-export([start_link/0,
         start_child/1]).

%% Supervisor callbacks
-export([init/1]).

-include("dikdik.hrl").

-define(SERVER, ?MODULE).

%%%===================================================================
%%% API functions
%%%===================================================================

-spec start_link() -> {ok, pid()} | any().
start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

start_child(DB) ->
    supervisor:start_child(?SERVER, [DB]).

%%%===================================================================
%%% Supervisor callbacks
%%%===================================================================

%% @private
init(_) ->
    Url = dikdik_app:config(db_url),
    {ok, {_Scheme, UserInfo, Host, Port, "/"++DBName, _Query}} = parse(Url),
    [Username, Password] = string:tokens(UserInfo, ":"),

    Overflow = list_to_integer(dikdik_app:config(db_max_overflow)),
    PoolSize = list_to_integer(dikdik_app:config(db_pool_size)),

    {ok, {{one_for_one, 1000, 3600}
         ,[poolboy:child_spec(?POOL, [{name, {local, dikdik_pool}}
                                     ,{worker_module, dikdik_db_worker}
                                     ,{size, PoolSize}
                                     ,{max_overflow, Overflow}], [
                                                                 {host, Host}
                                                                 ,{database, DBName}
                                                                 ,{port, Port}
                                                                 ,{user, Username}
                                                                 ,{password, Password}
                                                                 ,{ssl, true}
                                                                 ])]}}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%
%% %CopyrightBegin%
%%
%% Copyright Ericsson AB 2006-2012. All Rights Reserved.
%%
%% The contents of this file are subject to the Erlang Public License,
%% Version 1.1, (the "License"); you may not use this file except in
%% compliance with the License. You should have received a copy of the
%% Erlang Public License along with this software. If not, it can be
%% retrieved online at http://www.erlang.org/.
%%
%% Software distributed under the License is distributed on an "AS IS"
%% basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
%% the License for the specific language governing rights and limitations
%% under the License.
%%
%% %CopyrightEnd%
%%
%%
%% This is from chapter 3, Syntax Components, of RFC 3986:
%%
%% The generic URI syntax consists of a hierarchical sequence of
%% components referred to as the scheme, authority, path, query, and
%% fragment.
%%
%%    URI         = scheme ":" hier-part [ "?" query ] [ "#" fragment ]
%%
%%    hier-part   = "//" authority path-abempty
%%                   / path-absolute
%%                   / path-rootless
%%                   / path-empty
%%
%%    The scheme and path components are required, though the path may be
%%    empty (no characters).  When authority is present, the path must
%%    either be empty or begin with a slash ("/") character.  When
%%    authority is not present, the path cannot begin with two slash
%%    characters ("//").  These restrictions result in five different ABNF
%%    rules for a path (Section 3.3), only one of which will match any
%%    given URI reference.
%%
%%    The following are two example URIs and their component parts:
%%
%%          foo://example.com:8042/over/there?name=ferret#nose
%%          \_/   \______________/\_________/ \_________/ \__/
%%           |           |            |            |        |
%%        scheme     authority       path        query   fragment
%%           |   _____________________|__
%%          / \ /                        \
%%          urn:example:animal:ferret:nose
%%
%%    scheme      = ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )
%%    authority   = [ userinfo "@" ] host [ ":" port ]
%%    userinfo    = *( unreserved / pct-encoded / sub-delims / ":" )
%%
%%

%% -module(http_uri_r15b).

%% -export([parse/1, parse/2,
%%          scheme_defaults/0,
%%          encode/1, decode/1]).

%% -export_type([scheme/0, default_scheme_port_number/0]).


%%%=========================================================================
%%%  API
%%%=========================================================================

-type scheme() :: atom().
-type default_scheme_port_number() :: pos_integer().

-spec scheme_defaults() ->
    [{scheme(), default_scheme_port_number()}].

scheme_defaults() ->
    [{http,  80},
     {https, 443},
     {ftp,   21},
     {ssh,   22},
     {sftp,  22},
     {tftp,  69}].

parse(AbsURI) ->
    parse(AbsURI, []).

parse(AbsURI, Opts) ->
    case parse_scheme(AbsURI, Opts) of
        {error, Reason} ->
            {error, Reason};
        {Scheme, DefaultPort, Rest} ->
            case (catch parse_uri_rest(Scheme, DefaultPort, Rest, Opts)) of
                {ok, {UserInfo, Host, Port, Path, Query}} ->
                    {ok, {Scheme, UserInfo, Host, Port, Path, Query}};
                {error, Reason} ->
                    {error, {Reason, Scheme, AbsURI}};
                _  ->
                    {error, {malformed_url, Scheme, AbsURI}}
            end
    end.

%%%========================================================================
%%% Internal functions
%%%========================================================================

which_scheme_defaults(Opts) ->
    Key = scheme_defaults,
    case lists:keysearch(Key, 1, Opts) of
        {value, {Key, SchemeDefaults}} ->
            SchemeDefaults;
        false ->
            scheme_defaults()
    end.

parse_scheme(AbsURI, Opts) ->
    case split_uri(AbsURI, ":", {error, no_scheme}, 1, 1) of
        {error, no_scheme} ->
            {error, no_scheme};
        {SchemeStr, Rest} ->
            Scheme = list_to_atom(http_util:to_lower(SchemeStr)),
            SchemeDefaults = which_scheme_defaults(Opts),
            case lists:keysearch(Scheme, 1, SchemeDefaults) of
                {value, {Scheme, DefaultPort}} ->
                    {Scheme, DefaultPort, Rest};
                false ->
                    {Scheme, no_default_port, Rest}
            end
    end.

parse_uri_rest(Scheme, DefaultPort, "//" ++ URIPart, Opts) ->
    {Authority, PathQuery} =
        case split_uri(URIPart, "/", URIPart, 1, 0) of
            Split = {_, _} ->
                Split;
            URIPart ->
                case split_uri(URIPart, "\\?", URIPart, 1, 0) of
                    Split = {_, _} ->
                        Split;
                    URIPart ->
                        {URIPart,""}
                end
        end,
    {UserInfo, HostPort} = split_uri(Authority, "@", {"", Authority}, 1, 1),
    {Host, Port}         = parse_host_port(Scheme, DefaultPort, HostPort, Opts),
    {Path, Query}        = parse_path_query(PathQuery),
    {ok, {UserInfo, Host, Port, Path, Query}}.


parse_path_query(PathQuery) ->
    {Path, Query} =  split_uri(PathQuery, "\\?", {PathQuery, ""}, 1, 0),
    {path(Path), Query}.

%% In this version of the function, we no longer need
%% the Scheme argument, but just in case...
parse_host_port(_Scheme, DefaultPort, "[" ++ HostPort, Opts) -> %ipv6
    {Host, ColonPort} = split_uri(HostPort, "\\]", {HostPort, ""}, 1, 1),
    Host2 = maybe_ipv6_host_with_brackets(Host, Opts),
    {_, Port} = split_uri(ColonPort, ":", {"", DefaultPort}, 0, 1),
    {Host2, int_port(Port)};

parse_host_port(_Scheme, DefaultPort, HostPort, _Opts) ->
    {Host, Port} = split_uri(HostPort, ":", {HostPort, DefaultPort}, 1, 1),
    {Host, int_port(Port)}.

split_uri(UriPart, SplitChar, NoMatchResult, SkipLeft, SkipRight) ->
    case inets_regexp:first_match(UriPart, SplitChar) of
        {match, Match, _} ->
            {string:substr(UriPart, 1, Match - SkipLeft),
             string:substr(UriPart, Match + SkipRight, length(UriPart))};
        nomatch ->
            NoMatchResult
    end.

maybe_ipv6_host_with_brackets(Host, Opts) ->
    case lists:keysearch(ipv6_host_with_brackets, 1, Opts) of
        {value, {ipv6_host_with_brackets, true}} ->
            "[" ++ Host ++ "]";
        _ ->
            Host
    end.


int_port(Port) when is_integer(Port) ->
    Port;
int_port(Port) when is_list(Port) ->
    list_to_integer(Port);
%% This is the case where no port was found and there was no default port
int_port(no_default_port) ->
    throw({error, no_default_port}).

path("") ->
    "/";
path(Path) ->
    Path.
