open Core_kernel.Std

type path_segment =
  | Match of string
  | Param of string
  | Splat
  | FullSplat
  | Slash
with sexp

type matches = {
  params: (string * string) list;
  splat:  string list;
} with fields, sexp

type t = path_segment list with sexp

let parse_param s =
  if s = "/" then Slash
  else if s = "*" then Splat
  else if s = "**" then FullSplat
  else
    match String.chop_prefix s ~prefix:":" with
    | Some s -> Param s
    | None -> Match s

let of_list l = 
  let last_i = List.length l - 1 in
  l |> List.mapi ~f:(fun i s -> 
    match parse_param s with
    | FullSplat when i = last_i -> invalid_arg "** is only allowed at the end"
    | x -> x)

let split_slash_delim =
  let re = '/' |> Re.char |> Re.compile in
  fun path ->
    path
    |> Re.split_full re
    |> List.map ~f:(function
      | `Text s -> `Text s
      | `Delim subs -> `Delim (Re.get subs 0))

let split_slash path =
  path
  |> split_slash_delim
  |> List.map ~f:(function
    | `Text s
    | `Delim s -> s)

let of_string path = path |> split_slash |> of_list

let to_string l =
  let r =
    l |> List.filter_map ~f:(function
      | Match s   -> Some s
      | Param s   -> Some (":" ^ s)
      | Splat     -> Some "*"
      | FullSplat -> Some "**"
      | Slash     -> None)
    |> String.concat ~sep:"/" in
  "/" ^ r

let rec match_url t url ({params; splat} as matches) =
  match t, url with
  | [], []
  | FullSplat::[], _ -> Some matches
  | FullSplat::_, _ -> assert false (* splat can't be last *)
  | (Match x)::t, (`Text y)::url when x = y -> match_url t url matches
  | Slash::t, (`Delim _)::url -> match_url t url matches
  | Splat::t, (`Text s)::url ->
    match_url t url { matches with splat=((Uri.pct_decode s)::splat) }
  | (Param name)::t, (`Text p)::url ->
    match_url t url { matches with params=(name, (Uri.pct_decode p))::params }
  | Splat::_, (`Delim _)::_
  | Param _::_, `Delim _::_
  | (Match _)::_, _
  | Slash::_, _
  | _::_, []
  | [], _::_ -> None

let match_url t url =
  assert (url.[0] = '/');
  let path = url |> split_slash_delim in
  match_url t path {params=[]; splat=[]}
