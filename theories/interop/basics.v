From Coq Require Import ZArith.
From stdpp Require Import base gmap list.
From melocoton.interop Require Export assums params.

Section basics.
Context {WPms: WrapperParameters}.

(* block-level "logical" values and store *)

Definition lloc : Type := nat.
Implicit Type γ : lloc.

Inductive lval :=
  | Lint : Z → lval
  | Lloc : lloc → lval.

Inductive ismut := Mut | Immut.
(* Right now the tag is only used to distinguish between InjLV and InjRV (the
   constructors of the basic sum-type). In the future we might want to expand
   this to handle richer kinds of values. *)
Inductive tag : Type :=
  | TagDefault (* the default tag, used for InjLV and other blocks (pairs, refs, arrays) *)
  | TagInjRV (* the tag for InjRV *)
  .
Definition block :=
  (ismut * tag * list lval)%type.

Definition lloc_map : Type := gmap loc lloc.
Implicit Type χ : lloc_map.
Definition lstore : Type := gmap lloc block.
Implicit Type ζ : lstore.
Definition addr_map : Type := gmap lloc addr.
Implicit Type θ : addr_map.

Definition roots_map : Type := gmap addr lval.

(* block-level state changes *)

Inductive freeze_block : block → block → Prop :=
  | freeze_block_mut vs tg m' :
    freeze_block (Mut, tg, vs) (m', tg, vs)
  | freeze_block_refl b :
    freeze_block b b.

Definition freeze_lstore (ζ1 ζ2 : lstore) : Prop :=
  dom (gset lloc) ζ1 = dom (gset lloc) ζ2 ∧
  ∀ γ b1 b2, ζ1 !! γ = Some b1 → ζ2 !! γ = Some b2 →
    freeze_block b1 b2.

Inductive ML_change_block : block → block → Prop :=
  | mk_ML_change_block tg vs vs' :
    length vs = length vs' →
    ML_change_block (Mut, tg, vs) (Mut, tg, vs').

Definition ML_change_lstore (χ : lloc_map) (ζ1 ζ2 : lstore) : Prop :=
  dom (gset lloc) ζ1 ⊆ dom (gset lloc) ζ2 ∧
  ∀ γ b1 b2, ζ1 !! γ = Some b1 → ζ2 !! γ = Some b2 →
    (b1 = b2 ∨ (∃ ℓ, χ !! ℓ = Some γ ∧ ML_change_block b1 b2)).

Definition ML_extends_lloc_map (ζ : lstore) (χ1 χ2 : lloc_map) : Prop :=
  χ1 ⊆ χ2 ∧
  ∀ ℓ γ, χ1 !! ℓ = None → χ2 !! ℓ = Some γ → ζ !! γ = None.

Inductive modify_block : block → nat → lval → block → Prop :=
  | mk_modify_block tg vs i v :
    i < length vs →
    modify_block (Mut, tg, vs) i v (Mut, tg, (<[ i := v ]> vs)).

(* reachability *)

Inductive reachable : lstore → list lval → lloc → Prop :=
  | reachable_invals ζ γ vs :
    Lloc γ ∈ vs →
    reachable ζ vs γ
  | reachable_instore ζ vs γ γ' bvs m :
    reachable ζ vs γ' →
    ζ !! γ' = Some (m, bvs) →
    Lloc γ ∈ bvs →
    reachable ζ vs γ.

(* NB: the induction case for this definition of reachability where one takes a step last:

   --> = -->* -->

   TODO: prove an alternative induction principle that corresponds to the
   induction where one does a step first:

   --> = --> -->*
*)

(* C representation of block-level values, roots and memory *)

Inductive repr_lval : addr_map → lval → word → Prop :=
  | repr_lint θ x :
    repr_lval θ (Lint x) (encodeInt x)
  | repr_lloc θ γ a :
    θ !! γ = Some a →
    repr_lval θ (Lloc γ) (encodeAddr a).

Inductive repr_roots : addr_map → roots_map → memory → Prop :=
  | repr_roots_emp θ :
    repr_roots θ ∅ ∅
  | repr_roots_elem θ a v w roots mem :
    repr_roots θ roots mem →
    repr_lval θ v w →
    a ∉ dom (gset addr) roots →
    a ∉ dom (gset addr) mem →
    repr_roots θ (<[ a := v ]> roots) (<[ a := w ]> mem).

Definition repr (θ : addr_map) (roots : roots_map) (privmem mem : memory) : Prop :=
  ∃ memr, repr_roots θ roots memr ∧
  privmem ##ₘ memr ∧
  mem = memr ∪ privmem.

(* Block-level representation of ML values and store *)

Inductive is_val : lloc_map → lstore → val → lval → Prop :=
  (* non-loc base literals *)
  | is_val_int χ ζ x :
    is_val χ ζ (LitV (LitInt x)) (Lint x)
  | is_val_bool χ ζ b :
    is_val χ ζ (LitV (LitBool b)) (Lint (if b then 1 else 0))
  | is_val_unit χ ζ :
    is_val χ ζ (LitV LitUnit) (Lint 0)
  (* locations *)
  | is_val_loc χ ζ ℓ γ :
    χ !! ℓ = Some γ →
    is_val χ ζ (LitV (LitLoc ℓ)) (Lloc γ)
  (* pairs *)
  | is_val_pair χ ζ v1 v2 γ lv1 lv2 :
    ζ !! γ = Some (Immut, TagDefault, [lv1; lv2]) →
    is_val χ ζ v1 lv1 →
    is_val χ ζ v2 lv2 →
    is_val χ ζ (PairV v1 v2) (Lloc γ)
  (* sum-type constructors *)
  | is_val_injl χ ζ v lv γ :
    ζ !! γ = Some (Immut, TagDefault, [lv]) →
    is_val χ ζ v lv →
    is_val χ ζ (InjLV v) (Lloc γ)
  | is_val_injr χ ζ v lv γ :
    ζ !! γ = Some (Immut, TagInjRV, [lv]) →
    is_val χ ζ v lv →
    is_val χ ζ (InjRV v) (Lloc γ).

(* refs and arrays (stored in the ML store σ) all have the default tag. *)
Definition is_block_store (χ : lloc_map) (ζ : lstore) (σ : store) : Prop :=
  dom (gset loc) σ = dom (gset loc) χ ∧
  ∀ ℓ vs, σ !! ℓ = Some vs →
    ∃ γ lvs, χ !! ℓ = Some γ ∧
             ζ !! γ = Some (Mut, TagDefault, lvs) ∧
             Forall2 (is_val χ ζ) vs lvs.

Definition is_store (χ : lloc_map) (ζ : lstore) (privσ σ : store) : Prop :=
  ∃ σbks, is_block_store χ ζ σbks ∧
  privσ ##ₘ σbks ∧
  σ = σbks ∪ privσ.

End basics.
