open Sexplib

let return = Lwt.return
let (>>=) = Lwt.(>>=)
let (>>|) = Lwt.(>|=)

module Body = Cohttp_lwt_body

module Fn = struct
  let compose f g x = f (g x)
  let const x _ = x
end

module Option = struct
  let some x = Some x
  let value ~default = function
    | Some x -> x
    | None -> default
  let map ~f = function
    | None -> None
    | Some x -> Some (f x)
  let map2 ~f a b = match a,b with
    | Some x, Some y -> Some (f x y)
    | _ -> None
  let value_map ~default ~f = function
    | None -> default
    | Some x -> f x
  let try_with f =
    try Some (f ())
    with _ -> None
end

module List = struct
  include ListLabels

  let rec filter_map ~f = function
    | [] -> []
    | x :: l ->
        let l' = filter_map ~f l in
        match f x with
        | None -> l'
        | Some y -> y :: l'
  let is_empty = function [] -> true | _::_ -> false
  let rec find_map ~f = function
    | [] -> None
    | x :: l ->
        match f x with
        | Some _ as res -> res
        | None -> find_map ~f l
  let rec filter_opt = function
    | [] -> []
    | None :: l -> filter_opt l
    | Some x :: l -> x :: filter_opt l
  let sexp_of_t sexp_of_elem l = Sexp.List (map l ~f:sexp_of_elem)
end

module String = struct
  include String

  let is_prefix ~prefix s =
    String.length prefix <= String.length s &&
    (let i = ref 0 in
      while !i < String.length prefix && s.[!i] = prefix.[!i] do incr i done;
      !i = String.length prefix)

  let chop_prefix ~prefix s =
    assert (is_prefix ~prefix s);
    sub s (length prefix) (length s - length prefix)
end

module Queue = struct
  include Queue

  let find_map (type res) ~f q =
    let module M = struct exception E of res end in
    try
      Queue.iter
        (fun x -> match f x with None -> () | Some y -> raise (M.E y))
        q;
      None
    with M.E res -> Some res

  let t_of_sexp elem_of_sexp s = match s with
    | Sexp.List l ->
        let q = create () in
        List.iter (fun x -> push (elem_of_sexp x) q) l;
        q
    | Sexp.Atom _ -> raise (Conv.Of_sexp_error (Failure "expected list", s))

  let sexp_of_t sexp_of_elem q =
    let l = Queue.fold (fun acc x -> sexp_of_elem x :: acc) [] q in
    Sexp.List (List.rev l)
end

let sexp_of_pair f1 f2 (x1,x2) = Sexp.List [f1 x1; f2 x2]

let hashtbl_add_multi tbl x y =
  let l = try Hashtbl.find tbl x with Not_found -> [] in
  Hashtbl.replace tbl x (y::l)