
(* LISQL representations *)

(* LISQL constraints *)
type constr =
  | True
  | MatchesAll of string list
  | MatchesAny of string list
  | After of string
  | Before of string
  | FromTo of string * string
  | HigherThan of string
  | LowerThan of string
  | Between of string * string
  | HasLang of string
  | HasDatatype of string

let compile_constr constr : Rdf.term -> bool =
  let regexp_of_pat pat = Regexp.regexp_with_flag (Regexp.quote pat) "i" in
  let matches s re = Regexp.search re s 0 <> None in
  let leq t pat = try (Rdf.float_of_term t) <= (float_of_string pat) with _ -> false in
  let geq t pat = try (Rdf.float_of_term t) >= (float_of_string pat) with _ -> false in
  match constr with
    | True -> (fun t -> true)
    | MatchesAll lpat ->
      let lre = List.map regexp_of_pat lpat in
      (fun t ->
	let s = Rdf.string_of_term t in
	List.for_all (fun re -> matches s re) lre)
    | MatchesAny lpat ->
      let lre = List.map regexp_of_pat lpat in
      (fun t ->
	let s = Rdf.string_of_term t in
	List.exists (fun re -> matches s re) lre)
    | After pat ->
      (fun t -> (Rdf.string_of_term t) >= pat)
    | Before pat ->
      (fun t -> (Rdf.string_of_term t) <= pat)
    | FromTo (pat1,pat2) ->
      (fun t ->
	let s = Rdf.string_of_term t in
	pat1 <= s && s <= pat2)
    | HigherThan pat ->
      (fun t -> geq t pat)
    | LowerThan pat ->
      (fun t -> leq t pat)
    | Between (pat1,pat2) ->
      (fun t -> geq t pat1 && leq t pat2)
    | HasLang pat ->
      let re = regexp_of_pat pat in
      (function
	| Rdf.PlainLiteral (s,lang) -> matches lang re
	| _ -> false)
    | HasDatatype pat ->
      let re = regexp_of_pat pat in
      (function
	| Rdf.Number (_,s,dt)
	| Rdf.TypedLiteral (s,dt) -> matches dt re
	| _ -> false)

(* LISQL modifiers *)
type arg = S | P | O
type order = Unordered | Highest | Lowest
type aggreg = NumberOf | ListOf | Total | Average | Maximum | Minimum
type project = Unselect | Select | Aggreg of aggreg * order
type modif_s2 = project * order

(* LISQL elts *)
type elt_p1 =
  | Is of elt_s1
  | Type of Rdf.uri
  | Has of Rdf.uri * elt_s1
  | IsOf of Rdf.uri * elt_s1
  | Triple of arg * elt_s1 * elt_s1 (* abstraction arg + other S1 arguments in order: S, P, O *)
  | Search of constr
  | Filter of constr
  | And of elt_p1 array
  | Or of elt_p1 array
  | Maybe of elt_p1
  | Not of elt_p1
  | IsThere
and elt_s1 =
  | Det of elt_s2 * elt_p1 option
  | NAnd of elt_s1 array
  | NOr of elt_s1 array
  | NMaybe of elt_s1
  | NNot of elt_s1
and elt_s2 =
  | Term of Rdf.term
  | An of modif_s2 * elt_head
and elt_head =
  | Thing
  | Class of Rdf.uri
and elt_s =
  | Return of elt_s1

let top_p1 = IsThere
let top_s2 = An ((Select, Unordered), Thing)
let top_s1 = Det (top_s2,None)

let s2_of_term t = Term t
let s1_of_term t = Det (s2_of_term t, None)
let p1_of_term t = Is (s1_of_term t)

(* LISQL contexts *)
type ctx_p1 =
  | DetThatX of elt_s2 * ctx_s1
  | AndX of int * elt_p1 array * ctx_p1
  | OrX of int * elt_p1 array * ctx_p1
  | MaybeX of ctx_p1
  | NotX of ctx_p1
and ctx_s1 =
  | IsX of ctx_p1
  | HasX of Rdf.uri * ctx_p1
  | IsOfX of Rdf.uri * ctx_p1
  | TripleX1 of arg * elt_s1 * ctx_p1 (* context on first S1 arg *)
  | TripleX2 of arg * elt_s1 * ctx_p1 (* context on second S1 arg *)
  | ReturnX
  | NAndX of int * elt_s1 array * ctx_s1
  | NOrX of int * elt_s1 array * ctx_s1
  | NMaybeX of ctx_s1
  | NNotX of ctx_s1

(* LISQL focus *)
type focus =
  | AtP1 of elt_p1 * ctx_p1
  | AtS1 of elt_s1 * ctx_s1
  | AtS of elt_s

(* extraction of LISQL s element from focus *)

let rec elt_s_of_ctx_p1 (f : elt_p1) = function
  | DetThatX (det,ctx) -> elt_s_of_ctx_s1 (Det (det, Some f)) ctx
  | AndX (i,ar,ctx) -> ar.(i) <- f; elt_s_of_ctx_p1 (And ar) ctx
  | OrX (i,ar,ctx) -> ar.(i) <- f; elt_s_of_ctx_p1 (Or ar) ctx
  | MaybeX ctx -> elt_s_of_ctx_p1 (Maybe f) ctx
  | NotX ctx -> elt_s_of_ctx_p1 (Not f) ctx
and elt_s_of_ctx_s1 (f : elt_s1) = function
  | IsX ctx -> elt_s_of_ctx_p1 (Is f) ctx
  | HasX (p,ctx) -> elt_s_of_ctx_p1 (Has (p,f)) ctx
  | IsOfX (p,ctx) -> elt_s_of_ctx_p1 (IsOf (p,f)) ctx
  | TripleX1 (arg,np,ctx) -> elt_s_of_ctx_p1 (Triple (arg,f,np)) ctx
  | TripleX2 (arg,np,ctx) -> elt_s_of_ctx_p1 (Triple (arg,np,f)) ctx
  | ReturnX -> Return f
  | NAndX (i,ar,ctx) -> ar.(i) <- f; elt_s_of_ctx_s1 (NAnd ar) ctx
  | NOrX (i,ar,ctx) -> ar.(i) <- f; elt_s_of_ctx_s1 (NOr ar) ctx
  | NMaybeX ctx -> elt_s_of_ctx_s1 (NMaybe f) ctx
  | NNotX ctx -> elt_s_of_ctx_s1 (NNot f) ctx

let elt_s_of_focus = function
  | AtP1 (f,ctx) -> elt_s_of_ctx_p1 f ctx
  | AtS1 (f,ctx) -> elt_s_of_ctx_s1 f ctx
  | AtS f -> f

(* focus moves *)

let home_focus = AtS1 (top_s1, ReturnX)

let down_p1 (ctx : ctx_p1) : elt_p1 -> focus option = function
  | Is np -> Some (AtS1 (np, IsX ctx))
  | Type _ -> None
  | Has (p,np) -> Some (AtS1 (np, HasX (p,ctx)))
  | IsOf (p,np) -> Some (AtS1 (np, IsOfX (p,ctx)))
  | Triple (arg,np1,np2) -> Some (AtS1 (np1, TripleX1 (arg,np2,ctx)))
  | Search _ -> None
  | Filter _ -> None
  | And ar -> Some (AtP1 (ar.(0), AndX (0,ar,ctx)))
  | Or ar -> Some (AtP1 (ar.(0), OrX (0,ar,ctx)))
  | Maybe elt -> Some (AtP1 (elt, MaybeX ctx))
  | Not elt -> Some (AtP1 (elt, NotX ctx))
  | IsThere -> None
let down_s1 (ctx : ctx_s1) : elt_s1 -> focus option = function
  | Det (det,None) -> None
  | Det (An (modif, Thing), Some (IsOf (p,np))) -> Some (AtS1 (np, IsOfX (p, DetThatX (An (modif, Thing), ctx))))
  | Det (det, Some (And ar)) -> Some (AtP1 (ar.(0), AndX (0, ar, DetThatX (det, ctx))))
  | Det (det, Some rel) -> Some (AtP1 (rel, DetThatX (det,ctx)))
  | NAnd ar -> Some (AtS1 (ar.(0), NAndX (0,ar,ctx)))
  | NOr ar -> Some (AtS1 (ar.(0), NOrX (0,ar,ctx)))
  | NMaybe elt -> Some (AtS1 (elt, NMaybeX ctx))
  | NNot elt -> Some (AtS1 (elt, NNotX ctx))
let down_s : elt_s -> focus option = function
  | Return np -> Some (AtS1 (np,ReturnX))
let down_focus = function
  | AtP1 (f,ctx) -> down_p1 ctx f
  | AtS1 (f,ctx) -> down_s1 ctx f
  | AtS f -> down_s f

let rec up_p1 f = function
  | DetThatX (det,ctx) -> Some (AtS1 (Det (det, Some f), ctx))
  | AndX (i,ar,ctx) -> ar.(i) <- f; up_p1 (And ar) ctx (* Some (AtP1 (And ar, ctx)) *)
  | OrX (i,ar,ctx) -> ar.(i) <- f; Some (AtP1 (Or ar, ctx))
  | MaybeX ctx -> Some (AtP1 (Maybe f, ctx))
  | NotX ctx -> Some (AtP1 (Not f, ctx))
let rec up_s1 f = function
(*
  | HasX (p, DetThatX (An (modif, Thing), ctx)) -> Some (AtS1 (Det (An (modif, Thing), Some (Has (p,f))), ctx))
  | IsOfX (p, DetThatX (An (modif, Thing), ctx)) -> Some (AtS1 (Det (An (modif, Thing), Some (IsOf (p,f))), ctx))
*)
  | IsX ctx -> Some (AtP1 (Is f, ctx))
  | HasX (p,ctx) -> Some (AtP1 (Has (p,f), ctx))
  | IsOfX (p,ctx) -> Some (AtP1 (IsOf (p,f), ctx))
  | TripleX1 (arg,np,ctx) -> Some (AtP1 (Triple (arg,f,np), ctx))
  | TripleX2 (arg,np,ctx) -> Some (AtP1 (Triple (arg,np,f), ctx))
  | ReturnX -> Some (AtS (Return f))
  | NAndX (i,ar,ctx) -> ar.(i) <- f; up_s1 (NAnd ar) ctx
  | NOrX (i,ar,ctx) -> ar.(i) <- f; Some (AtS1 (NOr ar, ctx))
  | NMaybeX ctx -> Some (AtS1 (NMaybe f, ctx))
  | NNotX ctx -> Some (AtS1 (NNot f, ctx))
let up_focus = function
  | AtP1 (f,ctx) -> up_p1 f ctx
  | AtS1 (f,ctx) -> up_s1 f ctx
  | AtS f -> None

let right_p1 (f : elt_p1) : ctx_p1 -> focus option = function
  | DetThatX (det,ctx) -> None
  | AndX (i,ar,ctx) ->
    if i < Array.length ar - 1
    then begin
      ar.(i) <- f;
      Some (AtP1 (ar.(i+1), AndX (i+1, ar, ctx))) end
    else None
  | OrX (i,ar,ctx) ->
    if i < Array.length ar - 1
    then begin
      ar.(i) <- f;
      Some (AtP1 (ar.(i+1), OrX (i+1, ar, ctx))) end
    else None
  | MaybeX ctx -> None
  | NotX ctx -> None
let right_s1 (f : elt_s1) : ctx_s1 -> focus option = function
  | IsX _ -> None
  | HasX _ -> None
  | IsOfX _ -> None
  | TripleX1 (arg,np,ctx) -> Some (AtS1 (np, TripleX2 (arg,f,ctx)))
  | TripleX2 _ -> None
  | ReturnX -> None
  | NAndX (i,ar,ctx) ->
    if i < Array.length ar - 1
    then begin
      ar.(i) <- f;
      Some (AtS1 (ar.(i+1), NAndX (i+1, ar, ctx))) end
    else None
  | NOrX (i,ar,ctx) ->
    if i < Array.length ar - 1
    then begin
      ar.(i) <- f;
      Some (AtS1 (ar.(i+1), NOrX (i+1, ar, ctx))) end
    else None
  | NMaybeX ctx -> None
  | NNotX ctx -> None
let right_focus = function
  | AtP1 (f,ctx) -> right_p1 f ctx
  | AtS1 (f,ctx) -> right_s1 f ctx
  | AtS f -> None

let left_p1 (f : elt_p1) : ctx_p1 -> focus option = function
  | DetThatX (det,ctx) -> None
  | AndX (i,ar,ctx) ->
    if i > 0
    then begin
      ar.(i) <- f;
      Some (AtP1 (ar.(i-1), AndX (i-1, ar, ctx))) end
    else None
  | OrX (i,ar,ctx) ->
    if i > 0
    then begin
      ar.(i) <- f;
      Some (AtP1 (ar.(i-1), OrX (i-1, ar, ctx))) end
    else None
  | MaybeX ctx -> None
  | NotX ctx -> None
let left_s1 (f : elt_s1) : ctx_s1 -> focus option = function
  | IsX _ -> None
  | HasX _ -> None
  | IsOfX _ -> None
  | TripleX1 _ -> None
  | TripleX2 (arg,np,ctx) -> Some (AtS1 (np, TripleX1 (arg,f,ctx)))
  | ReturnX -> None
  | NAndX (i,ar,ctx) ->
    if i > 0
    then begin
      ar.(i) <- f;
      Some (AtS1 (ar.(i-1), NAndX (i-1, ar, ctx))) end
    else None
  | NOrX (i,ar,ctx) ->
    if i > 0
    then begin
      ar.(i) <- f;
      Some (AtS1 (ar.(i-1), NOrX (i-1, ar, ctx))) end
    else None
  | NMaybeX ctx -> None
  | NNotX ctx -> None
let left_focus = function
  | AtP1 (f,ctx) -> left_p1 f ctx
  | AtS1 (f,ctx) -> left_s1 f ctx
  | AtS f -> None

let rec focus_moves (steps : (focus -> focus option) list) (foc_opt : focus option) : focus option = (* makes as many steps as possible *)
  match steps, foc_opt with
    | _, None -> None
    | [], _ -> foc_opt
    | step::others, Some foc ->
      ( match step foc with
	| None -> Some foc
	| Some foc' -> focus_moves others (Some foc') )

(* increments *)

type increment =
  | IncrTerm of Rdf.term
  | IncrIs
  | IncrClass of Rdf.uri
  | IncrProp of Rdf.uri
  | IncrInvProp of Rdf.uri
  | IncrTriple of arg
  | IncrTriplify
  | IncrAnd
  | IncrOr
  | IncrMaybe
  | IncrNot
  | IncrUnselect
  | IncrAggreg of aggreg
  | IncrOrder of order

let term_of_increment : increment -> Rdf.term option = function
  | IncrTerm t -> Some t
  | IncrClass c -> Some (Rdf.URI c)
  | IncrProp p -> Some (Rdf.URI p)
  | IncrInvProp p -> Some (Rdf.URI p)
  | IncrTriple arg -> None
  | IncrTriplify -> None
  | IncrIs -> None
  | IncrAnd -> None
  | IncrOr -> None
  | IncrMaybe -> None
  | IncrNot -> None
  | IncrUnselect -> None
  | IncrAggreg _ -> None
  | IncrOrder order -> None

let append_and_p1 ctx elt_p1 = function
  | And ar ->
    let n = Array.length ar in
    let ar2 = Array.make (n+1) elt_p1 in
    Array.blit ar 0 ar2 0 n;
    AtP1 (elt_p1, AndX (n, ar2, ctx))
  | p1 ->
    AtP1 (elt_p1, AndX (1, [|p1; elt_p1|], ctx))
let append_or_p1 ctx elt_p1 = function
  | Or ar ->
    let n = Array.length ar in
    let ar2 = Array.make (n+1) elt_p1 in
    Array.blit ar 0 ar2 0 n;
    AtP1 (elt_p1, OrX (n, ar2, ctx))
  | p1 ->
    AtP1 (elt_p1, OrX (1, [|p1; elt_p1|], ctx))

let append_and_s1 ctx elt_s1 = function
  | NAnd ar ->
    let n = Array.length ar in
    let ar2 = Array.make (n+1) elt_s1 in
    Array.blit ar 0 ar2 0 n;
    AtS1 (elt_s1, NAndX (n, ar2, ctx))
  | s1 ->
    AtS1 (elt_s1, NAndX (1, [|s1; elt_s1|], ctx))
let append_or_s1 ctx elt_s1 = function
  | NOr ar ->
    let n = Array.length ar in
    let ar2 = Array.make (n+1) elt_s1 in
    Array.blit ar 0 ar2 0 n;
    AtS1 (elt_s1, NOrX (n, ar2, ctx))
  | s1 ->
    AtS1 (elt_s1, NOrX (1, [|s1; elt_s1|], ctx))

let insert_elt_p1 elt = function
  | AtP1 (IsThere, ctx) -> Some (AtP1 (elt, ctx))
  | AtP1 (f, AndX (i,ar,ctx)) -> ar.(i) <- f; Some (append_and_p1 ctx elt (And ar))
  | AtP1 (f, ctx) -> Some (append_and_p1 ctx elt f)
  | AtS1 (Det (det, None), ctx) -> Some (AtP1 (elt, DetThatX (det,ctx)))
  | AtS1 (Det (det, Some rel), ctx) -> Some (append_and_p1 (DetThatX (det,ctx)) elt rel)
  | AtS1 _ -> None (* no insertion of increments on complex NPs *)
  | AtS _ -> None

let insert_term t focus =
  let focus2_opt =
    match focus with
(*
      | AtP1 (f, DetThatX (det,ctx)) ->
	if det = Term t
	then Some (AtP1 (f, DetThatX (top_s2, ctx)))
	else Some (AtP1 (f, DetThatX (Term t, ctx)))
*)
      | AtP1 _ -> insert_elt_p1 (p1_of_term t) focus
      | AtS1 (Det (det,rel_opt), ctx) ->
	if det = Term t
	then Some (AtS1 (Det (top_s2, rel_opt), ctx))
	else Some (AtS1 (Det (Term t, rel_opt), ctx))
      | AtS1 _ -> None (* no insertion of terms on complex NPs *)
      | _ -> None in
  match focus2_opt with
    | Some (AtS1 (f, HasX (p, ctx))) -> Some (AtP1 (Has (p,f), ctx))
    | Some (AtS1 (f, IsOfX (p, ctx))) -> Some (AtP1 (IsOf (p,f), ctx))
    | Some (AtS1 (f, TripleX1 (arg,np,ctx))) -> Some (AtP1 (Triple (arg,f,np), ctx))
    | Some (AtS1 (f, TripleX2 (arg,np,ctx))) -> Some (AtP1 (Triple (arg,np,f), ctx))
    | other -> other

let insert_class c = function
  | AtS1 (Det (det,rel_opt), ctx) ->
    ( match det with
      | Term _ ->
	Some (AtS1 (Det (An ((Select, Unordered), Class c), rel_opt), ctx))
      | An (modif, Thing) ->
	Some (AtS1 (Det (An (modif, Class c), rel_opt), ctx))
      | An (modif, Class c2) when c2 = c ->
	Some (AtS1 (Det (An (modif, Thing), rel_opt), ctx))
      | _ ->
	let rel = match rel_opt with None -> IsThere | Some rel -> rel in
	insert_elt_p1 (Type c) (AtP1 (rel, DetThatX (det, ctx))) )
  | focus -> insert_elt_p1 (Type c) focus

let insert_property p focus =
  let foc_opt = insert_elt_p1 (Has (p, top_s1)) focus in
  focus_moves [down_focus] foc_opt

let insert_inverse_property p focus =
  let foc_opt = insert_elt_p1 (IsOf (p, top_s1)) focus in
  focus_moves [down_focus] foc_opt

let insert_triple arg focus =
  let foc_opt = insert_elt_p1 (Triple (arg, top_s1, top_s1)) focus in
  let steps = if arg = S then [down_focus; right_focus] else [down_focus] in
  focus_moves steps foc_opt

let insert_triplify = function
  | AtP1 (Has (p,np), ctx) -> Some (AtP1 (Triple (S, Det (Term (Rdf.URI p), None), np), ctx))
  | AtP1 (IsOf (p,np), ctx) -> Some (AtP1 (Triple (O, np, Det (Term (Rdf.URI p), None)), ctx))
  | AtP1 (Triple (S, Det (Term (Rdf.URI p), _), np), ctx) -> Some (AtP1 (Has (p,np), ctx))
  | AtP1 (Triple (O, np, Det (Term (Rdf.URI p), _)), ctx) -> Some (AtP1 (IsOf (p,np), ctx))
  | _ -> None

let insert_constr constr focus =
  match focus with
    | AtS1 (f, ReturnX) when f = top_s1 -> insert_elt_p1 (Search constr) focus
    | _ -> insert_elt_p1 (Filter constr) focus

let insert_is focus =
  let foc_opt = insert_elt_p1 (Is top_s1) focus in
  focus_moves [down_focus] foc_opt

let insert_and = function
  | AtP1 (And ar, ctx) -> Some (append_and_p1 ctx IsThere (And ar))
  | AtP1 (f, AndX (i,ar,ctx2)) -> ar.(i) <- f; Some (append_and_p1 ctx2 IsThere (And ar))
  | AtP1 (f, ctx) -> Some (append_and_p1 ctx IsThere f)
  | AtS1 (NAnd ar, ctx) -> Some (append_and_s1 ctx top_s1 (NAnd ar))
  | AtS1 (f, NAndX (i,ar,ctx2)) -> ar.(i) <- f; Some (append_and_s1 ctx2 top_s1 (NAnd ar))
  | AtS1 (f, ctx) -> Some (append_and_s1 ctx top_s1 f)
  | _ -> None

let insert_or = function
  | AtP1 (Or ar, ctx) -> Some (append_or_p1 ctx IsThere (Or ar))
  | AtP1 (f, OrX (i,ar,ctx2)) -> ar.(i) <- f; Some (append_or_p1 ctx2 IsThere (Or ar))
  | AtP1 (f, ctx) -> Some (append_or_p1 ctx IsThere f)
  | AtS1 (NOr ar, ctx) -> Some (append_or_s1 ctx top_s1 (NOr ar))
  | AtS1 (f, NOrX (i,ar,ctx2)) -> ar.(i) <- f; Some (append_or_s1 ctx2 top_s1 (NOr ar))
  | AtS1 (f, ctx) -> Some (append_or_s1 ctx top_s1 f)
  | _ -> None

let insert_maybe = function
  | AtP1 (Maybe f, ctx) -> Some (AtP1 (f,ctx))
  | AtP1 (f, ctx) -> if f = top_p1 then Some (AtP1 (f, MaybeX ctx)) else Some (AtP1 (Maybe f, ctx))
  | AtS1 (NMaybe f, ctx) -> Some (AtS1 (f,ctx))
  | AtS1 (f, ctx) -> if f = top_s1 then Some (AtS1 (f, NMaybeX ctx)) else Some (AtS1 (NMaybe f, ctx))
  | _ -> None

let insert_not = function
  | AtP1 (Not f, ctx) -> Some (AtP1 (f,ctx))
  | AtP1 (f, ctx) -> if f = top_p1 then Some (AtP1 (f, NotX ctx)) else Some (AtP1 (Not f, ctx))
  | AtS1 (NNot f, ctx) -> Some (AtS1 (f,ctx))
  | AtS1 (f, ctx) -> if f = top_s1 then Some (AtS1 (f, NNotX ctx)) else Some (AtS1 (NNot f, ctx))
  | _ -> None

let insert_modif_transf f = function
  | AtS1 (Det (An (modif, head), rel_opt), ctx) ->
    let modif2 = f modif in
    let foc2 = AtS1 (Det (An (modif2, head), rel_opt), ctx) in
    ( match fst modif2 with
      | Unselect | Aggreg _ -> up_focus foc2 (* to enforce visible aggregation *)
      | _ -> Some foc2 )
  | _ -> None

let insert_increment incr focus =
  match incr with
    | IncrTerm t -> insert_term t focus
    | IncrClass c -> insert_class c focus
    | IncrProp p -> insert_property p focus
    | IncrInvProp p -> insert_inverse_property p focus
    | IncrTriple arg -> insert_triple arg focus
    | IncrTriplify -> insert_triplify focus
    | IncrIs -> insert_is focus
    | IncrAnd -> insert_and focus
    | IncrOr -> insert_or focus
    | IncrMaybe -> insert_maybe focus
    | IncrNot -> insert_not focus
    | IncrUnselect ->
      insert_modif_transf
	(function
	  | (Unselect,order) -> Select, order
	  | (_,order) ->  Unselect, order)
	focus
    | IncrAggreg g ->
      insert_modif_transf
	(function
	  | (Aggreg (g0, gorder), order) when g = g0 -> Select, order
	  | (_, order) -> Aggreg (g, Unordered), order)
	focus
    | IncrOrder order ->
      insert_modif_transf
	(function
	  | (Aggreg (g,gorder), order0) -> 
	    if gorder = order
	    then Aggreg (g, Unordered), order0
	    else Aggreg (g, order), order0
	  | ((Select | Unselect) as proj, order0) ->
	    if order0 = order
	    then proj, Unordered
	    else proj, order)
	focus

let delete_array ar i =
  let n = Array.length ar in
  if n = 1 then `Empty
  else if n = 2 then `Single ar.(1-i)
  else
    let ar2 = Array.make (n-1) ar.(0) in
    Array.blit ar 0 ar2 0 i;
    Array.blit ar (i+1) ar2 i (n-i-1);
    if i = n-1 && i > 0 (* last elt is deleted *)
    then `Array (ar2, i-1)
    else `Array (ar2, i)

let rec delete_ctx_p1 = function
  | DetThatX (det,ctx) -> Some (AtS1 (Det (det,None), ctx))
  | AndX (i,ar,ctx) ->
    ( match delete_array ar i with
      | `Empty -> delete_ctx_p1 ctx
      | `Single elt -> Some (AtP1 (elt, ctx))
      | `Array (ar2,i2) -> Some (AtP1 (ar2.(i2), AndX (i2,ar2,ctx))) )
  | OrX (i,ar,ctx) ->
    ( match delete_array ar i with
      | `Empty -> delete_ctx_p1 ctx
      | `Single elt -> Some (AtP1 (elt, ctx))
      | `Array (ar2, i2) -> Some (AtP1 (ar2.(i2), OrX (i2, ar2, ctx))) )
  | MaybeX ctx -> delete_ctx_p1 ctx
  | NotX ctx -> delete_ctx_p1 ctx
and delete_ctx_s1 f ctx =
  match ctx with
    | IsX _
    | HasX _
    | IsOfX _
    | TripleX1 _
    | TripleX2 _ 
    | ReturnX -> if f = top_s1 then None else Some (AtS1 (top_s1, ctx))
    | NAndX (i,ar,ctx2) ->
      ( match delete_array ar i with
	| `Empty -> delete_ctx_s1 top_s1 ctx2
	| `Single elt -> Some (AtS1 (elt, ctx2))
	| `Array (ar2,i2) -> Some (AtS1 (ar2.(i2), NAndX (i2,ar2,ctx2))) )
    | NOrX (i,ar,ctx2) ->
      ( match delete_array ar i with
	| `Empty -> delete_ctx_s1 top_s1 ctx2
	| `Single elt -> Some (AtS1 (elt, ctx2))
	| `Array (ar2, i2) -> Some (AtS1 (ar2.(i2), NOrX (i2, ar2, ctx2))) )
    | NMaybeX ctx2 -> delete_ctx_s1 f ctx2
    | NNotX ctx2 -> delete_ctx_s1 f ctx2

let delete_focus = function
  | AtP1 (_, ctx) -> delete_ctx_p1 ctx
  | AtS1 (f, ctx) -> delete_ctx_s1 f ctx
  | AtS _ -> Some (AtS (Return top_s1))
