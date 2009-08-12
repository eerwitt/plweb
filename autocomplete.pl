/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@cs.vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 2009, VU University Amsterdam

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(autocomplete_predicates,
	  [
	  ]).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_path)).
:- use_module(library(http/http_parameters)).
:- use_module(library(http/http_json)).
:- use_module(library(http/html_head)).
:- use_module(library(http/html_write)).
:- use_module(library(option)).
:- use_module(library(apply)).
:- use_module(library(occurs)).
:- use_module(yui_resources).

:- multifile
	prolog:doc_search_field//1.

:- http_handler(root(autocomplete/ac_predicate), ac_predicate, []).

%	prolog:doc_search_field(+Options) is det.

prolog:doc_search_field(Options) -->
	{ select_option(size(W), Options, Options1),
	  atomic_concat(W, ex, Wem)
	},
	autocomplete(ac_predicate,
		     [ query_delay(0.5),
		       auto_highlight(false),
		       width(Wem)
		     | Options1
		     ]).

%%	autocomplete(+HandlerID, +Options)// is det.
%
%	Insert a YUI autocomplete widget that obtains its alternatives
%	from HandlerID.  The following Options are supported:
%
%	    * width(+Width)
%	    Specify the width of the box.  Width must satisfy the CSS
%	    length syntax.
%
%	    * query_delay(+Seconds)
%	    Wait until no more keys are typed for Seconds before sending
%	    the query to the server.

autocomplete(Handler, Options) -->
	{ http_location_by_id(Handler, Path),
	  atom_concat(Handler, '_complete', CompleteID),
	  atom_concat(Handler, '_input', InputID),
	  atom_concat(Handler, '_container', ContainerID),
	  select_option(width(Width), Options, Options1, '25em'),
	  select_option(name(Name), Options1, Options2, predicate),
	  select_option(value(Value), Options2, Options3, '')
	},
	html([ \html_requires(yui('autocomplete/autocomplete.js')),
	       \html_requires(yui('autocomplete/assets/skins/sam/autocomplete.css')),
	       div(id(CompleteID),
		   [ input([ id(InputID),
			     name(Name),
			     value(Value),
			     type(text)
			   ]),
		     div(id(ContainerID), [])
		   ]),
	       style(type('text/css'),
		     [ '#', CompleteID, '\n',
		       '{ width:~w; padding-bottom:0em; display:inline-block; vertical-align:top}'-[Width]
		     ]),
	       \autocomplete_script(Path, InputID, ContainerID, Options3)
	     ]).

autocomplete_script(HandlerID, Input, Container, Options) -->
	{ http_absolute_location(HandlerID, Path, [])
	},
	html(script(type('text/javascript'), [
'{ \n',
'  var oDS = new YAHOO.util.XHRDataSource("~w");\n'-[Path],
'  oDS.responseType = YAHOO.util.XHRDataSource.TYPE_JSON;\n',
'  oDS.responseSchema = { resultsList:"results",
			  fields:["label"]
			};\n',
'  oDS.maxCacheEntries = 5;\n',
'  var oAC = new YAHOO.widget.AutoComplete("~w", "~w", oDS);\n'-[Input, Container],
\ac_options(Options),
'}\n'
					     ])).
ac_options([]) -->
	[].
ac_options([H|T]) -->
	ac_option(H),
	ac_options(T).

ac_option(query_delay(Time)) --> !,
	html([ '  oAC.queryDelay = ~w;\n'-[Time] ]).
ac_option(auto_highlight(Bool)) --> !,
	html([ '  oAC.autoHighlight = ~w;\n'-[Bool] ]).
ac_option(O) -->
	{ domain_error(yui_autocomplete_option, O) }.

%%	ac_predicate(+Request)
%
%	HTTP handler to reply autocompletion

ac_predicate(Request) :-
	http_parameters(Request,
			[ query(Query, [])
			]),
	autocompletions(Query, Count, Completions),
	reply_json(json([ query = json([ count=Count
				       ]),
			  results = Completions
			])).

autocompletions(Query, Count, Completions) :-
	findall(C, completion(Query, C), Completions0),
	sort(Completions0, Completions1),
	length(Completions1, Count),
	first_n(10, Completions1, Completions2),
	maplist(obj_result, Completions2, Completions).

completion(Query, Name-Obj) :-
	prolog:doc_object_summary(Obj, _Type, _Section, _Summary),
	completion_target(Obj, Name),
	sub_atom(Name, 0, _, _, Query).

completion_target(Name/_,   Name).
completion_target(_:Name/_, Name).
completion_target(c(Name),  Name).

obj_result(Obj, json([label=Label])) :-
	obj_name(Obj, Label).

obj_name(_-c(Function), Name) :- !,
	atom_concat(Function, '()', Name).
obj_name(_-(_:Term), Name) :- !,
	format(atom(Name), '~w', [Term]).
obj_name(_-Term, Name) :-
	format(atom(Name), '~w', [Term]).

first_n(0, _, []) :- !.
first_n(_, [], []) :- !.
first_n(N, [H|T0], [H|T]) :-
	N2 is N - 1,
	first_n(N2, T0, T).
