From stdpp Require Import relations strings gmap.
From iris.base_logic.lib Require Import own.
From iris.algebra Require Import ofe.
From iris.algebra Require Import auth excl excl_auth gmap.
From iris.proofmode Require Import tactics.
From iris.prelude Require Import options.

Definition gmap_inj `{Countable K} {V} (m : gmap K V) :=
  ∀ k1 k2 v, m !! k1 = Some v → m !! k2 = Some v → k1 = k2.

Section language_commons.
  Context {val : Type}.
  (** Classifying expressions into values and calls. *)
  Inductive mixin_expr_class :=
  | ExprVal (v : val) : mixin_expr_class
  | ExprCall (fn_name : string) (arg : list val) : mixin_expr_class.
End language_commons.

Lemma excl_auth_eq A `{inG Σ (excl_authR (leibnizO A))} γ (x y: A):
  own γ (◯E (x:leibnizO A)) -∗ own γ (●E (y:leibnizO A)) -∗ ⌜x = y⌝.
Proof.
  iIntros "H1 H2". iDestruct (own_op with "[$H1 $H2]") as "H".
  iDestruct (own_valid with "H") as %HH%excl_auth_agree. done.
Qed.

Lemma excl_auth_upd `{!inG Σ (excl_authR (leibnizO A))} γ (x y z: A):
  own γ (◯E (x:leibnizO A)) -∗ own γ (●E (y:leibnizO A)) ==∗
  own γ (◯E (z:leibnizO A)) ∗ own γ (●E (z:leibnizO A)).
Proof.
  iIntros "H1 H2".
  iDestruct (own_update_2 with "H1 H2") as ">[? ?]".
  1: by apply excl_auth_update. iModIntro. iFrame.
Qed.

Lemma excl_auth_alloc A `{inG Σ (excl_authR (leibnizO A))} (x: A):
  ⊢ |==> ∃ γ, own γ (◯E (x:leibnizO A)) ∗ own γ (●E (x:leibnizO A)).
Proof.
  iIntros.
  iMod (own_alloc (●E (x:leibnizO A) ⋅ ◯E (x:leibnizO A))) as (γ) "[? ?]".
  1: by apply excl_auth_valid. iModIntro. iExists _. iFrame.
Qed.
