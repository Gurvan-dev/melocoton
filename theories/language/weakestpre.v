From iris.proofmode Require Import base proofmode classes.
From iris.base_logic.lib Require Export fancy_updates.
From melocoton.language Require Export language.
(* FIXME: If we import iris.bi.weakestpre earlier texan triples do not
   get pretty-printed correctly. *)
From iris.bi Require Export weakestpre.
From iris.prelude Require Import options.
Import uPred.

Class melocotonGS_gen 
  (hlc : has_lc) (val : Type) 
  (Λ : language val) (Σ : gFunctors) := IrisG {
  iris_invGS :> invGS_gen hlc Σ;

  (** The state interpretation is an invariant that should hold in
  between each step of reduction. Here [Λstate] is the global state,
  the first [nat] is the number of steps already performed by the
  program, [list (observation Λ)] are the remaining observations, and the
  last [nat] is the number of forked-off threads (not the total number
  of threads, which is one higher because there is always a main
  thread). *)
  state_interp : state Λ → nat → iProp Σ;

  (** When performing pure steps, the state interpretation needs to be
  adapted for the change in the [ns] parameter.

  Note that we use an empty-mask fancy update here. We could also use
  a basic update or a bare magic wand, the expressiveness of the
  framework would be the same. If we removed the modality here, then
  the client would have to include the modality it needs as part of
  the definition of [state_interp]. Since adding the modality as part
  of the definition [state_interp_mono] does not significantly
  complicate the formalization in Iris, we prefer simplifying the
  client. *)
  state_interp_mono σ ns E:
    state_interp σ ns ={E}=∗ state_interp σ (S ns)
}.
Global Opaque iris_invGS.
Global Arguments IrisG {hlc val Λ Σ}.

Notation melocotonGS := (melocotonGS_gen HasLc).

Definition wp_pre `{!melocotonGS_gen hlc val Λ Σ} 
    (p:mixin_prog Λ.(func))
    (T: string -d> list val -d> (val -d> iPropO Σ) -d> iPropO Σ)
    (wp : coPset -d>
          expr Λ -d>
          (val -d> iPropO Σ) -d>
          iPropO Σ) :
    coPset -d>
    expr Λ -d>
    (val -d> iPropO Σ) -d>
    iPropO Σ := λ E e Φ,
    (∀ σ ns, state_interp σ ns ={E}=∗
      (  (∃ v, ⌜e = of_class Λ (ExprVal v)⌝ ∗ state_interp σ ns ∗ Φ v)
       ∨ (∃ s vv K, ⌜e = fill K (of_class Λ (ExprCall s vv))⌝ ∗ ⌜p !! s = None⌝ ∗
          |={E}=>
            (∃ Ξ, state_interp σ ns ∗ T s vv Ξ ∗  ▷ ∀ r, Ξ r -∗ wp E (fill K (of_class Λ (ExprVal r))) Φ))
       ∨ ((⌜reducible_no_threads p e σ⌝ ∗
                    ∀ σ' e', ⌜prim_step p e σ e' σ' []⌝ -∗  |={E}=> ▷ |={E}=> 
                        (state_interp σ' (S ns) ∗ wp E e' Φ)))))%I.

Local Instance wp_pre_contractive `{!melocotonGS_gen hlc val Λ Σ}
     {p:mixin_prog Λ.(func)} T : Contractive (wp_pre p T).
Proof.
  rewrite /wp_pre /= => n wp wp' Hwp E e1 Φ. cbn in Hwp.
  repeat (f_contractive || f_equiv || apply Hwp || intros ?).
Qed.

Record prog_environ `{!melocotonGS_gen hlc val Λ Σ} := {
  prog : mixin_prog (func Λ);
  T : string -d> list val -d> (val -d> iPropO Σ) -d> iPropO Σ
}.

Local Definition wp_def `{!melocotonGS_gen hlc val Λ Σ} : Wp (iProp Σ) (expr Λ) (val) (prog_environ) :=
  λ p : (prog_environ), fixpoint (wp_pre (p.(prog)) (p.(T))).
Local Definition wp_aux : seal (@wp_def). Proof. by eexists. Qed.
Definition wp' := wp_aux.(unseal).
Global Arguments wp' {hlc val Λ Σ _}.
Global Existing Instance wp'.
Local Lemma wp_unseal `{!melocotonGS_gen hlc val Λ Σ} : wp = @wp_def hlc val Λ Σ _.
Proof. rewrite -wp_aux.(seal_eq) //. Qed.

Section wp.
Context `{!melocotonGS_gen hlc val Λ Σ}.
Implicit Types P : iProp Σ.
Implicit Types Φ : val → iProp Σ.
Implicit Types v : val.
Implicit Types e : expr Λ.
Implicit Types T : string -d> list val -d> (val -d> iPropO Σ) -d> iPropO Σ.
Implicit Types prog : mixin_prog (func Λ).
Implicit Types pe : prog_environ.

(* Weakest pre *)
Lemma wp_unfold pe E e Φ :
  WP e @ pe; E {{ Φ }} ⊣⊢ wp_pre (pe.(prog)) (pe.(T)) (wp (PROP:=iProp Σ) pe) E e Φ.
Proof. rewrite wp_unseal. apply (fixpoint_unfold (wp_pre (pe.(prog)) (pe.(T)))). Qed.

Global Instance wp_ne pe E e n :
  Proper (pointwise_relation _ (dist n) ==> dist n) (wp (PROP:=iProp Σ) pe E e).
Proof.
  revert e. induction (lt_wf n) as [n _ IH]=> e Φ Ψ HΦ.
  rewrite !wp_unfold /wp_pre /=.
  do 15 f_equiv. 1: do 6 f_equiv.
  all: f_contractive.
  all: f_equiv.
  all: f_equiv.
  1: f_equiv.
  all: apply IH; eauto; intros k; eapply dist_le', HΦ; lia.
Qed.
Global Instance wp_proper pe E e :
  Proper (pointwise_relation _ (≡) ==> (≡)) (wp (PROP:=iProp Σ) pe E e).
Proof.
  by intros Φ Φ' ?; apply equiv_dist=>n; apply wp_ne=>v; apply equiv_dist.
Qed.

(*
Global Instance wp_contractive pe E e n :
  (∀ v,e <> of_class Λ (ExprVal v)) ->
  Proper (pointwise_relation _ (dist_later n) ==> dist n) (wp (PROP:=iProp Σ) pe E e).
Proof.
Admitted.
*)
(*
Lemma wp_value_fupd' pe E Φ v : WP (of_class Λ (ExprVal v)) @ pe; E {{ Φ }} ⊣⊢ |={E}=> Φ v.
Proof. 
Admitted.
*)

(* TODO usually we show the other way around *)

Lemma wp_value_fupd' pe E Φ v : (|={E}=> Φ v)%I ⊢ WP (of_class Λ (ExprVal v)) @ pe; E {{ Φ }}.
Proof.
  rewrite !wp_unfold /wp_pre /=.
  iIntros "H %σ %ns Hσ". iLeft. iMod "H". iModIntro. iExists _; iFrame; done.
Qed.


Definition prog_environ_mono pe1 pe2 : Prop := 
   prog pe1 = prog pe2
/\ ∀ (s:string) vv Φ, ⌜s ∉ (dom (prog pe1))⌝ -∗ T pe1 s vv Φ -∗ T pe2 s vv Φ.

Lemma prog_environ_mono_refl : Reflexive (prog_environ_mono).
Proof. intros s; split; eauto. Qed.
#[local] Hint Resolve prog_environ_mono_refl : core.

Lemma wp_strong_mono pe1 pe2 E1 E2 e Φ Ψ :
  E1 ⊆ E2 → prog_environ_mono pe1 pe2 ->
  WP e @ pe1; E1 {{ Φ }} -∗ (∀ v, Φ v ={E2}=∗ Ψ v) -∗ WP e @ pe2; E2 {{ Ψ }}.
Proof.
  iIntros (HE (Hpe1 & Hpe2)) "H HΦ". iLöb as "IH" forall (e E1 E2 HE Φ Ψ).
  rewrite !wp_unfold /wp_pre /=.
  iIntros "%σ %ns Hσ". iSpecialize ("H" $! σ ns with "Hσ").
  iMod (fupd_mask_subseteq E1) as "Hclose"; first done.
  iMod "H".
  iDestruct "H" as "[(%x & -> & Hσ & H)|[(%s & %vv & %K & -> & %H2 & H3)|H3]]".
  - iMod "Hclose". iLeft. iExists x. iFrame. iSplitR; first done. 
    iApply ("HΦ" with "[> -]"). by iApply (fupd_mask_mono E1 _); first apply HE.
  - iRight; iLeft. iExists s, vv, K. iMod "H3". iMod "Hclose".
    iModIntro. iSplitR; first done. iSplitR; first (iPureIntro; congruence).
    iModIntro.
    iDestruct "H3" as "(%Ξ & Hσ & HT & Hr)".
    iExists Ξ. iFrame. iSplitL "HT"; first iApply (Hpe2 s vv with "[] HT").
    1: iPureIntro; by apply not_elem_of_dom_2.
    iNext. iIntros "%r HΞ". iApply ("IH" $! (fill K (of_class Λ (ExprVal r))) E1 E2 HE Φ Ψ with "[Hr HΞ] HΦ").
    iApply ("Hr" with "HΞ").
  - do 2 iRight. 
    iDestruct "H3" as "(HH & H3)".
    rewrite Hpe1.  iMod "Hclose". iFrame. iModIntro. iIntros "%σ2 %e' Hstep".
    iSpecialize ("H3" $! σ2 e' with "Hstep").
    iMod (fupd_mask_subseteq E1) as "Hclose2"; first done. iMod "H3".
    iMod "Hclose2". iModIntro. iModIntro.
    iMod (fupd_mask_subseteq E1) as "Hclose2'"; first done.
    iMod "H3" as "(Hσ & HWP)".
    iMod "Hclose2'". iModIntro.
    iFrame. iApply ("IH" $! e' E1 E2 HE Φ Ψ with "HWP HΦ").
Qed.

Lemma fupd_wp pe E e Φ : (|={E}=> WP e @ pe; E {{ Φ }}) ⊢ WP e @ pe; E {{ Φ }}.
Proof.
  rewrite wp_unfold /wp_pre. iIntros "H %σ %ns Hσ".
  iMod "H". iApply ("H" $! σ ns with "Hσ").
Qed.

Lemma wp_fupd s E e Φ : WP e @ s; E {{ v, |={E}=> Φ v }} ⊢ WP e @ s; E {{ Φ }}.
Proof. iIntros "H". iApply (wp_strong_mono s s E with "H"); auto. Qed.

(*
Lemma wp_atomic pe E1 E2 e Φ :
  (|={E}=> WP e @ pe; E2 {{ v, |={E2,E1}=> Φ v }}) ⊢ WP e @ pe; E1 {{ Φ }}.
Proof.
Qed. *) 

(** In this stronger version of [wp_step_fupdN], the masks in the
   step-taking fancy update are a bit weird and somewhat difficult to
   use in practice. Hence, we prove it for the sake of completeness,
   but [wp_step_fupdN] is just a little bit weaker, suffices in
   practice and is easier to use.

   See the statement of [wp_step_fupdN] below to understand the use of
   ordinary conjunction here.


 *)

Lemma wp_step_fupdN_strong n pe E e P Φ :
  TCEq (to_val e) None →
  (∀ σ ns, state_interp σ ns
       ={E}=∗ ⌜n ≤ 1⌝) ∧
  ((|={E}=>  |={E}▷=>^n |={E}=> P) ∗
    WP e @ pe; E {{ v, P ={E}=∗ Φ v }}) -∗
  WP e @ pe; E {{ Φ }}.
Proof.
  destruct n as [|n].
  { iIntros (?) "/= [_ [HP Hwp]]".
    iApply (wp_strong_mono with "Hwp"); [done..|].
    iIntros (v) "H". iApply ("H" with "[>HP]"). by do 2 iMod "HP". }
  rewrite !wp_unfold /wp_pre /=. iIntros (Heq) "H".
  iIntros (σ1 ns) "Hσ".
  destruct (decide (n = 0)) as [->|Hn]; first last.
  { iDestruct "H" as "[Hn _]". iMod ("Hn" with "Hσ") as %?. lia. }
  iDestruct "H" as "[_ [>HP Hwp]]".
  iMod ("Hwp" $! σ1 ns with "Hσ") as "[(%z & -> & Hσ & H)|[(%s & %vv & %K & -> & H2 & H3)|(%Hred & H3)]]".
  + unfold to_val in Heq. rewrite to_of_class in Heq.
    exfalso. apply TCEq_eq in Heq. congruence.
  + cbn. iRight. iLeft. iMod "HP". iMod "H3" as "(%Ξ & Hσ & Hvv & HΞ)".
    iExists s, vv, K. iModIntro. iFrame. iSplitR; first done. iModIntro.
    iExists Ξ. iFrame. iNext.
    iIntros "%r Hr". iSpecialize ("HΞ" $! r with "Hr").
    iApply (wp_strong_mono pe pe E E with "HΞ [HP]"). 1-2:easy.
    iIntros "%v Hv". iMod ("Hv" with "HP") as "HP". do 2 iMod "HP". iModIntro. iAssumption.
  + iMod "HP". iModIntro. iRight. iRight. iSplitR; first done.
    iIntros "%σ' %e' %Hstep". iSpecialize ("H3" $! σ' e' Hstep). iMod "H3". iModIntro. iModIntro.
    iMod "H3" as "(Hσ' & H3)". do 2 iMod "HP". iModIntro.
    iFrame.
    iApply (wp_strong_mono pe pe E E with "H3 [HP]"). 1-2:easy.
    iIntros "%v Hv". iMod ("Hv" with "HP"). iAssumption.
Qed.


Lemma wp_step_fupd pe E e P Φ :
  TCEq (to_val e) None →
  ((|={E}=>  ▷ |={E}=> P) ∗
    WP e @ pe; E {{ v, P ={E}=∗ Φ v }}) -∗
  WP e @ pe; E {{ Φ }}.
Proof.
  iIntros (H) "(H1 & H2)".
  iApply (wp_step_fupdN_strong 1). iSplitR.
  - iIntros; iModIntro; done.
  - iSplitR "H2"; last iApply "H2". iMod "H1". do 4 iModIntro. iApply "H1".
Qed.

Lemma wp_step pe E e P Φ :
  TCEq (to_val e) None →
  ( ▷ P) -∗
    WP e @ pe; E {{ v, P ={E}=∗ Φ v }} -∗
  WP e @ pe; E {{ Φ }}.
Proof.
  iIntros (H) "H1 H2".
  iApply (wp_step_fupd). iSplitL "H1".
  - do 3 iModIntro. iApply "H1".
  - iApply "H2".
Qed.

(*

Lemma wp_bind K `{!LanguageCtx K} pe E e Φ :
  WP e @ pe; E {{ v, WP K (of_class _ (ExprVal v)) @ pe; E {{ Φ }} }} ⊢ WP K e @ pe; E {{ Φ }}.

*)

Lemma wp_bind K pe E e Φ :
  WP e @ pe; E {{ v, WP fill K (of_class _ (ExprVal v)) @ pe; E {{ Φ }} }} ⊢ WP fill K e @ pe; E {{ Φ }}.
Proof.
  iIntros "H". iLöb as "IH" forall (E e Φ). rewrite !wp_unfold /wp_pre.
  iIntros "%σ %ns Hσ".
  iMod ("H" $! σ ns with "Hσ") as "[(%x & -> & Hσ & H)|[(%s & %vv & %K' & -> & H2 & H3)|H3]]".
  - rewrite {1} wp_unfold /wp_pre.
    iMod ("H" $! σ ns with "Hσ") as "H". iApply "H".
  - iMod "H3" as "(%Ξ & Hσ & HT & Hr)".
    iModIntro. iRight. iLeft. iExists s, vv, (comp_ectx K K'). 
    iFrame. iSplitR.
    {iPureIntro. now rewrite fill_comp. }
    iModIntro. iExists Ξ. iFrame. iNext.
    iIntros "%r HΞ".
    rewrite <- fill_comp.
    iApply "IH". iApply ("Hr" with "HΞ").
  - iRight. iRight. iModIntro. iDestruct "H3" as "(%Hred & H3)".
    iSplitR; first eauto using reducible_no_threads_fill.
    iIntros "%σ' %e' %Hstep".
    pose proof (reducible_not_val _ _ _ (reducible_no_threads_reducible _ _ _ K Hred)) as  Hnone.
    destruct (fill_step_inv _ _ _ _ _ _ _ Hnone Hstep) as (e2'' & -> & H4).
    iSpecialize ("H3" $! σ' e2'' H4). iMod "H3". do 2 iModIntro.
    iMod "H3" as "(Hσ & H3)". iModIntro. iFrame.
    iApply "IH". iApply "H3".
Qed.

Lemma wp_bind_inv K s E e Φ :
  WP fill K e @ s; E {{ Φ }} ⊢ WP e @ s; E {{ v, WP fill K (of_class _ (ExprVal v)) @ s; E {{ Φ }} }}.
Proof.
  iIntros "H".
  iLöb as "IH" forall (E e Φ). do 2 rewrite {1} wp_unfold /wp_pre /=.
  assert ((exists v, e = of_val _ v) \/ (forall v, e <> of_val _ v)) as [[v Hv]|Hnv].
  1: { destruct (to_val e) as [v|] eqn:Heq.
       + left. exists v. now apply of_to_val in Heq.
       + right. intros v ->. rewrite to_of_val in Heq. congruence. }
  1: { rewrite Hv.
       iIntros "%σ %ns Hσ". iModIntro. iLeft. iExists v. iFrame. iSplitR; first done.
       rewrite {1} wp_unfold /wp_pre /=. iApply "H". }
  iIntros "%σ %ns Hσ".
  iMod ("H" $! σ ns with "Hσ") as "[(%x & %H1 & Hσ & H)|[(%s' & %vv & %K' & %H1 & %H2 & H3)|(%Hred & H3)]]".
  - destruct (fill_class' K e) as [->|[v Hv]].
    + eexists. rewrite H1. now rewrite to_of_class.
    + rewrite fill_empty in H1. exfalso. eapply Hnv. apply H1.
    + apply of_to_class in Hv. exfalso. eapply Hnv. rewrite <- Hv. easy.
  - destruct (call_in_ctx _ _ _ _ _ H1) as [[K'' ->]|[x Hx]].
    + rewrite <- fill_comp in H1. apply fill_inj in H1. subst.
      iMod "H3" as "(%Ξ & Hσ & HT & Hr)".
      iRight. iLeft. iExists s', vv, K''.
      iSplitR; first done. iModIntro. iSplitR; first done.
      iModIntro. iExists Ξ. iFrame. iNext.
      iIntros (r) "HΞr".
      iApply "IH". rewrite fill_comp. by iApply "Hr".
    + unfold to_val in Hx. destruct (to_class e) as [[v|]|] eqn:Heq; try congruence.
      * exfalso. eapply Hnv. apply of_to_class in Heq. rewrite <- Heq. easy.
      * exfalso. rewrite <- Hx in Heq. rewrite to_of_class in Heq. congruence.
      * exfalso. rewrite <- Hx in Heq. rewrite to_of_class in Heq. congruence.
  - iModIntro.
    iRight. iRight. iSplitR. 1: iPureIntro.
    { destruct Hred as (e'&σ'&(e''&->&H2)%fill_step_inv). 1: by eexists e'',σ'.
      destruct (to_val e) eqn:Heq; try congruence. exfalso. apply (Hnv v). apply of_to_val in Heq. done. }
    iIntros (σ' e' Hred').
    iSpecialize ("H3" $! σ' _ (fill_prim_step _ K e _ _ _ _ Hred')). iMod "H3". do 2 iModIntro.
    iMod "H3" as "(Hσ & HWP)". iModIntro. iFrame.
    iApply "IH". iFrame.
Qed.

(** * Derived rules *)
Lemma wp_mono pe E e Φ Ψ : (∀ v, Φ v ⊢ Ψ v) → WP e @ pe; E {{ Φ }} ⊢ WP e @ pe; E {{ Ψ }}.
Proof.
  iIntros (HΦ) "H"; iApply (wp_strong_mono with "H"); auto. 
  iIntros (v) "?". by iApply HΦ.
Qed.
Lemma wp_pe_mono pe1 pe2 E e Φ :
  prog_environ_mono pe1 pe2 → WP e @ pe1; E {{ Φ }} ⊢ WP e @ pe2; E {{ Φ }}.
Proof. iIntros (?) "H". iApply (wp_strong_mono with "H"); auto. Qed.
Lemma wp_mask_mono s E1 E2 e Φ : E1 ⊆ E2 → WP e @ s; E1 {{ Φ }} ⊢ WP e @ s; E2 {{ Φ }}.
Proof. iIntros (?) "H"; iApply (wp_strong_mono with "H"); auto. Qed.
Global Instance wp_mono' s E e :
  Proper (pointwise_relation _ (⊢) ==> (⊢)) (wp (PROP:=iProp Σ) s E e).
Proof. by intros Φ Φ' ?; apply wp_mono. Qed.
Global Instance wp_flip_mono' s E e :
  Proper (pointwise_relation _ (flip (⊢)) ==> (flip (⊢))) (wp (PROP:=iProp Σ) s E e).
Proof. by intros Φ Φ' ?; apply wp_mono. Qed.

Lemma wp_value' s E Φ v : Φ v ⊢ WP (of_val _ v) @ s; E {{ Φ }}.
Proof. iIntros "H". iApply wp_value_fupd'. iAssumption. Qed.

Lemma wp_value s E Φ e v : to_val e = Some v -> Φ v ⊢ WP e @ s; E {{ Φ }}.
Proof. intros H.
  assert (e = of_val _ v) as ->.
  - unfold of_val. unfold to_val in H. destruct (to_class e) as [[]|] eqn:Heq; cbn in H; try congruence.
    apply of_to_class in Heq. congruence.
  - apply wp_value'.
Qed.
  

Lemma wp_frame_l s E e Φ R : R ∗ WP e @ s; E {{ Φ }} ⊢ WP e @ s; E {{ v, R ∗ Φ v }}.
Proof. iIntros "[? H]". iApply (wp_strong_mono with "H"); auto with iFrame. Qed.
Lemma wp_frame_r s E e Φ R : WP e @ s; E {{ Φ }} ∗ R ⊢ WP e @ s; E {{ v, Φ v ∗ R }}.
Proof. iIntros "[H ?]". iApply (wp_strong_mono with "H"); auto with iFrame. Qed.

(*
Lemma wp_step_fupd s E1 E2 e P Φ :
  TCEq (to_val e) None → E2 ⊆ E1 →
  (|={E1}[E2]▷=> P) -∗ WP e @ s; E2 {{ v, P ={E1}=∗ Φ v }} -∗ WP e @ s; E1 {{ Φ }}.
Proof.
  iIntros (??) "HR H".
  iApply (wp_step_fupdN_strong _ E1 E2 with "[-]"); [done|..]. iSplit.
  - iIntros (????) "_". iMod (fupd_mask_subseteq ∅) as "_"; [set_solver+|].
    auto with lia.
  - iFrame "H". iMod "HR" as "$". auto.
Qed.

Lemma wp_frame_step_l s E1 E2 e Φ R :
  TCEq (to_val e) None → E2 ⊆ E1 →
  (|={E1}[E2]▷=> R) ∗ WP e @ s; E2 {{ Φ }} ⊢ WP e @ s; E1 {{ v, R ∗ Φ v }}.
Proof.
  iIntros (??) "[Hu Hwp]". iApply (wp_step_fupd with "Hu"); try done.
  iApply (wp_mono with "Hwp"). by iIntros (?) "$$".
Qed.
Lemma wp_frame_step_r s E1 E2 e Φ R :
  TCEq (to_val e) None → E2 ⊆ E1 →
  WP e @ s; E2 {{ Φ }} ∗ (|={E1}[E2]▷=> R) ⊢ WP e @ s; E1 {{ v, Φ v ∗ R }}.
Proof.
  rewrite [(WP _ @ _; _ {{ _ }} ∗ _)%I]comm; setoid_rewrite (comm _ _ R).
  apply wp_frame_step_l.
Qed.
Lemma wp_frame_step_l' s E e Φ R :
  TCEq (to_val e) None → ▷ R ∗ WP e @ s; E {{ Φ }} ⊢ WP e @ s; E {{ v, R ∗ Φ v }}.
Proof. iIntros (?) "[??]". iApply (wp_frame_step_l s E E); try iFrame; eauto. Qed.
Lemma wp_frame_step_r' s E e Φ R :
  TCEq (to_val e) None → WP e @ s; E {{ Φ }} ∗ ▷ R ⊢ WP e @ s; E {{ v, Φ v ∗ R }}.
Proof. iIntros (?) "[??]". iApply (wp_frame_step_r s E E); try iFrame; eauto. Qed.
*)
Lemma wp_wand s E e Φ Ψ :
  WP e @ s; E {{ Φ }} -∗ (∀ v, Φ v -∗ Ψ v) -∗ WP e @ s; E {{ Ψ }}.
Proof.
  iIntros "Hwp H". iApply (wp_strong_mono with "Hwp"); auto.
  iIntros (?) "?". by iApply "H".
Qed.
Lemma wp_wand_l s E e Φ Ψ :
  (∀ v, Φ v -∗ Ψ v) ∗ WP e @ s; E {{ Φ }} ⊢ WP e @ s; E {{ Ψ }}.
Proof. iIntros "[H Hwp]". iApply (wp_wand with "Hwp H"). Qed.
Lemma wp_wand_r s E e Φ Ψ :
  WP e @ s; E {{ Φ }} ∗ (∀ v, Φ v -∗ Ψ v) ⊢ WP e @ s; E {{ Ψ }}.
Proof. iIntros "[Hwp H]". iApply (wp_wand with "Hwp H"). Qed.
Lemma wp_frame_wand s E e Φ R :
  R -∗ WP e @ s; E {{ v, R -∗ Φ v }} -∗ WP e @ s; E {{ Φ }}.
Proof.
  iIntros "HR HWP". iApply (wp_wand with "HWP").
  iIntros (v) "HΦ". by iApply "HΦ".
Qed.


Lemma wp_extern' (s:prog_environ) n vv E Φ :
     ⌜((weakestpre.prog s) : gmap string _) !! n = None⌝ 
  -∗ (|={E}=> (weakestpre.T s n vv Φ))
  -∗ WP of_class _ (ExprCall n vv) @ s ; E {{v, Φ v}}.
Proof.
  iIntros (Hlookup) "HT".
  rewrite !wp_unfold /wp_pre /=.
  iIntros "%σ %ns Hσ". iMod "HT". iModIntro. iRight. iLeft.
  iExists _,_,empty_ectx. iSplitR.
  1: by rewrite fill_empty. iSplitR.
  1: done.
  iModIntro. iExists Φ. iFrame. iNext.
  iIntros (r) "Hr". rewrite fill_empty.
  by iApply wp_value'.
Qed.


Lemma wp_extern K (s:prog_environ) n vv E Φ :
     ⌜((weakestpre.prog s) : gmap string _) !! n = None⌝ 
  -∗ (|={E}=> (weakestpre.T s n vv (λ v, WP fill K (of_class Λ (ExprVal v)) @ s; E {{ v', Φ v' }})))
  -∗ WP fill K (of_class _ (ExprCall n vv)) @ s ; E {{v, Φ v}}.
Proof.
  iIntros (Hlookup) "HT".
  iApply wp_bind.
  iApply (wp_wand with "[HT]").
  1: iApply (wp_extern' with "[] [HT]"). 1: done. 1: iApply "HT".
  iIntros (v) "Hv"; iApply "Hv".
Qed.


Lemma wp_call' (s:prog_environ) n funn body' vv E Φ :
     ⌜((weakestpre.prog s) : gmap string _) !! n = Some funn⌝ 
  -∗ ⌜apply_func funn vv = Some body'⌝
  -∗ (|={E}=> ▷ |={E}=> WP body' @ s ; E {{v, Φ v}})
  -∗ WP of_class _ (ExprCall n vv) @ s ; E {{v, Φ v}}.
Proof.
  iIntros (Hlookup Happly) "Hcont".
  rewrite (wp_unfold _ _ (of_class Λ (ExprCall n vv))) /wp_pre /=.
  iIntros "%σ %ns Hσ". iMod "Hcont". do 2 iRight.
  iModIntro. iSplitR.
  { iPureIntro. apply head_prim_reducible_no_threads.
    eexists _,_. apply call_head_step.
    eexists funn. done. }
  iIntros (σ' e' Hstep) "!>!>".
  apply head_reducible_prim_step in Hstep. 2: { eexists _,_,_. apply call_head_step; eexists funn; done. }
  apply call_head_step in Hstep. destruct Hstep as (fn' & Hfn' & He' & -> & _).
  iMod (state_interp_mono with "Hσ") as "Hσ".
  iMod "Hcont".
  iModIntro. iFrame. assert (e' = body') as -> by congruence. done.
Qed.



Lemma wp_link pe pe_extended F k E e Φ :
  ⌜ k ∉ dom (prog pe) ⌝
  -∗ ⌜ prog pe_extended = <[ k := F ]> (prog pe) ⌝ 
  -∗ (□ (∀ (s:string) vv Ψ, ⌜s ∉ (dom (prog pe)) ∧ s <> k⌝ -∗ T pe s vv Ψ -∗ T (pe_extended) s vv Ψ))
  -∗ (□ (∀ vv Ψ, T pe k vv Ψ -∗ WP (of_class Λ (ExprCall k vv)) @ (pe_extended); E {{v, Ψ v}}))
  -∗ WP e @ pe; E {{v, Φ v}}
  -∗ WP e @ (pe_extended); E {{v, Φ v}}.
Proof.
  iIntros (HnE HE) "#Hs2T #Hs1T H". iLöb as "IH" forall (e Φ).
  rewrite !wp_unfold /wp_pre /=.
  iIntros "%σ %ns Hσ". iSpecialize ("H" $! σ ns with "Hσ").
  iMod "H".
  iDestruct "H" as "[(%x & -> & Hσ & H)|[(%s & %vv & %K & -> & %H2 & H3)|(%HH & H3)]]".
  - iLeft. iExists x. iFrame. iModIntro. done.
  - iMod "H3" as "(%Ξ & Hσ & HT & Hcont)". destruct (decide (k = s)) as [->|Hne]. 
    + iPoseProof ("Hs1T" with "HT") as "HT'".
      rewrite !(@wp_unfold pe_extended E (of_class Λ (ExprCall s vv))) /wp_pre /=.
      iMod ("HT'" $! σ ns with "Hσ") as "HT'".
      iDestruct "HT'" as "[ (%x & %Hcontr & Hσ & H) |[ (%s' & %vv' & %K' & %Hcontr & %H2' & H3') |(%HH' & H3)]]".
      { exfalso.
        enough (to_class (of_class Λ (ExprCall s vv)) = to_class (of_class Λ (ExprVal x))) by
          (repeat rewrite to_of_class in H; congruence).
        congruence. }
      { exfalso.
        destruct (fill_class K' (of_class Λ (ExprCall s' vv'))) as [->|HR].
        - rewrite <- Hcontr. rewrite to_of_class. by eexists.
        - rewrite fill_empty in Hcontr. 
          assert (to_class (of_class Λ (ExprCall s vv)) = to_class (of_class Λ (ExprCall s' vv'))) as H by congruence.
          do 2 rewrite to_of_class in H. assert (s' = s) as -> by congruence.
          rewrite HE in H2'. rewrite lookup_insert in H2'. congruence.
        - unfold to_val in HR. rewrite to_of_class in HR. by destruct HR. }
      iModIntro.
      iRight. iRight.
      iSplitR.
      { iPureIntro. eapply reducible_no_threads_fill. done. }
      iIntros "%σ' %e' %Hstep".
      apply fill_reducible_prim_step in Hstep.
      2: { by eapply reducible_no_threads_reducible. }
      destruct Hstep as (e'' & -> & Hstep).
      iSpecialize ("H3" $! σ' _ Hstep). iMod "H3". do 1 iModIntro. iNext. iMod "H3" as "(H31 & H32)".
      iModIntro. iFrame. iApply wp_bind. iApply (wp_wand with "[H32]").
      * iApply "H32".
      * iIntros (v) "Hv". iSpecialize ("Hcont" $! v with "Hv"). iApply "IH". done.
    + iPoseProof ("Hs2T" with "[] HT") as "HT'"; first iPureIntro.
      { split; try congruence. by apply not_elem_of_dom_2. }
      iModIntro. iRight. iLeft. iExists s, vv, K.
      iSplitR; first done. iSplitR.
      { iPureIntro. rewrite HE. by rewrite lookup_insert_ne. }
      iModIntro. iExists Ξ. iFrame. iNext. iIntros (r) "Hr". iApply "IH".
      iApply ("Hcont" with "Hr").
  - iModIntro. iRight. iRight.
    destruct HH as (? & σ' & (K & e1' & e2' & -> & -> & HH)%prim_step_inv).
    destruct (to_class e1') as [[v|s vv]|] eqn:Heq.
    + apply of_to_class in Heq. rewrite <- Heq in HH. exfalso. eapply val_head_step. done.
    + apply of_to_class in Heq. subst e1'. apply call_head_step_inv in HH.
      destruct HH as (fn & Hs & Hfn & -> & _). assert (k ≠ s) as Hne.
      { intros ->. apply elem_of_dom_2 in Hs. done. }
      iSplitR.
      { iPureIntro. eexists _,_. econstructor. 1-2:done. apply call_head_step.
        exists fn; repeat split; try done. rewrite HE. by rewrite lookup_insert_ne. }
      iIntros (σ' e' Hstep).
      assert (prim_step (prog pe) (fill K (of_class Λ (ExprCall s vv))) σ (fill K e2') σ []) as Hstep'.
      { econstructor. 1-2:done. eapply call_head_step. exists fn; repeat split; done. }
      apply head_reducible_prim_step_ctx in Hstep; last first.
      1: eexists _, _, _; apply call_head_step; eexists; repeat split; try done;
         rewrite HE; by rewrite lookup_insert_ne.
      destruct Hstep as (e3 & Heq3 & (ffn & Heq4 & Heq5 & -> & _)%call_head_step_inv).
      iSpecialize ("H3" $! _ _ Hstep').
      iMod "H3". iModIntro. iNext. iMod "H3" as "(Hσ' & HWP)". iModIntro.
      iFrame. iApply "IH". enough (e' = fill K e2') as -> by done.
      rewrite HE in Heq4. rewrite lookup_insert_ne in Heq4; last done.
      rewrite Hs in Heq4. congruence.
    + iSplitR.
      { iPureIntro. eexists _,_. eapply head_step_no_call in HH. 
        1: econstructor; first done; first done.
        1: apply HH. 1: done. (*
        rewrite HE. apply insert_subseteq. by apply not_elem_of_dom_1. *) }
      iIntros (σ'' e'' Hstep).
      apply head_reducible_prim_step_ctx in Hstep; last first.
      { eexists _,_,_. eapply head_step_no_call in HH. 
        1: apply HH. 1: done. (*
        rewrite HE. apply insert_subseteq. by apply not_elem_of_dom_1. *) }
      destruct Hstep as (e2'' & -> & Hstep).
      eapply head_step_no_call in Hstep; last done.
      iMod ("H3" $! _ _ (Prim_step _ _ _ _ _ _ _ _ _ eq_refl eq_refl Hstep)) as "H3".
      iModIntro. iNext. iMod "H3" as "(Hσ'' & Hfill)". iModIntro. iFrame.
      iApply "IH". iFrame.
  Qed.

Lemma wp_link_rec pe pe_extended F k E e Φ :
  ⌜ k ∉ dom (prog pe) ⌝
  -∗ ⌜ prog pe_extended = <[ k := F ]> (prog pe) ⌝ 
  -∗ (□ (∀ (s:string) vv Ψ, ⌜s ∉ (dom (prog pe)) ∧ s <> k⌝ -∗ T pe s vv Ψ -∗ T (pe_extended) s vv Ψ))
  -∗ (□ (∀ vv Ψ, T pe k vv Ψ -∗ match apply_func F vv with None => ⌜False⌝ | Some e =>  WP e @ (pe); E {{v, Ψ v}} end))
  -∗ WP e @ pe; E {{v, Φ v}}
  -∗ WP e @ (pe_extended); E {{v, Φ v}}.
Proof.
  iIntros (HnE HE) "#Hs2T #Hs1T H". iLöb as "IH" forall (e Φ).
  rewrite !wp_unfold /wp_pre /=.
  iIntros "%σ %ns Hσ". iSpecialize ("H" $! σ ns with "Hσ").
  iMod "H".
  iDestruct "H" as "[(%x & -> & Hσ & H)|[(%s & %vv & %K & -> & %H2 & H3)|(%HH & H3)]]".
  - iLeft. iExists x. iFrame. iModIntro. done.
  - iMod "H3" as "(%Ξ & Hσ & HT & Hcont)". destruct (decide (k = s)) as [->|Hne]. 
    + iPoseProof ("Hs1T" with "HT") as "HT'".
      destruct (apply_func F vv) as [e'|] eqn:Heq; try done.
      iRight. iRight. iModIntro.
      assert (head_step (prog pe_extended) (of_class Λ (ExprCall s vv)) σ e' σ []) as Hstepy.
      1: apply call_head_step; exists F; split; first (rewrite HE; by rewrite lookup_insert); by repeat split.
      iSplitR.
      1: iPureIntro; eexists _,_; by econstructor.
      iIntros (σ' e'' (e2'' & -> & (F' & HeqF' & HeqF'a & -> & HH)%call_head_step_inv)%head_reducible_prim_step_ctx).
      2: do 3 eexists; done.
      iModIntro. iNext. iMod (state_interp_mono with "Hσ" ) as "Hσ". iModIntro. iFrame.
      iApply "IH". rewrite HE in HeqF'. rewrite (lookup_insert) in HeqF'. iApply wp_bind.
      assert (e' = e2'') as -> by congruence.
      iApply (wp_wand with "HT'").
      iIntros (v) "Hv". iApply ("Hcont" $! v with "Hv").
    + iPoseProof ("Hs2T" with "[] HT") as "HT'"; first iPureIntro.
      { split; try congruence. by apply not_elem_of_dom_2. }
      iModIntro. iRight. iLeft. iExists s, vv, K.
      iSplitR; first done. iSplitR.
      { iPureIntro. rewrite HE. by rewrite lookup_insert_ne. }
      iModIntro. iExists Ξ. iFrame. iNext. iIntros (r) "Hr". iApply "IH".
      iApply ("Hcont" with "Hr").
  - iModIntro. iRight. iRight.
    destruct HH as (? & σ' & (K & e1' & e2' & -> & -> & HH)%prim_step_inv).
    destruct (to_class e1') as [[v|s vv]|] eqn:Heq.
    + apply of_to_class in Heq. rewrite <- Heq in HH. exfalso. eapply val_head_step. done.
    + apply of_to_class in Heq. subst e1'. apply call_head_step_inv in HH.
      destruct HH as (fn & Hs & Hfn & -> & _). assert (k ≠ s) as Hne.
      { intros ->. apply elem_of_dom_2 in Hs. done. }
      iSplitR.
      { iPureIntro. eexists _,_. econstructor. 1-2:done. apply call_head_step.
        exists fn; repeat split; try done. rewrite HE. by rewrite lookup_insert_ne. }
      iIntros (σ' e' Hstep).
      assert (prim_step (prog pe) (fill K (of_class Λ (ExprCall s vv))) σ (fill K e2') σ []) as Hstep'.
      { econstructor. 1-2:done. eapply call_head_step. exists fn; repeat split; done. }
      apply head_reducible_prim_step_ctx in Hstep; last first.
      1: eexists _, _, _; apply call_head_step; eexists; repeat split; try done;
         rewrite HE; by rewrite lookup_insert_ne.
      destruct Hstep as (e3 & Heq3 & (ffn & Heq4 & Heq5 & -> & _)%call_head_step_inv).
      iSpecialize ("H3" $! _ _ Hstep').
      iMod "H3". iModIntro. iNext. iMod "H3" as "(Hσ' & HWP)". iModIntro.
      iFrame. iApply "IH". enough (e' = fill K e2') as -> by done.
      rewrite HE in Heq4. rewrite lookup_insert_ne in Heq4; last done.
      rewrite Hs in Heq4. congruence.
    + iSplitR.
      { iPureIntro. eexists _,_. eapply head_step_no_call in HH. 
        1: econstructor; first done; first done.
        1: apply HH. 1: done. (*
        rewrite HE. apply insert_subseteq. by apply not_elem_of_dom_1. *) }
      iIntros (σ'' e'' Hstep).
      apply head_reducible_prim_step_ctx in Hstep; last first.
      { eexists _,_,_. eapply head_step_no_call in HH. 
        1: apply HH. 1: done. (*
        rewrite HE. apply insert_subseteq. by apply not_elem_of_dom_1. *) }
      destruct Hstep as (e2'' & -> & Hstep).
      eapply head_step_no_call in Hstep; last done.
      iMod ("H3" $! _ _ (Prim_step _ _ _ _ _ _ _ _ _ eq_refl eq_refl Hstep)) as "H3".
      iModIntro. iNext. iMod "H3" as "(Hσ'' & Hfill)". iModIntro. iFrame.
      iApply "IH". iFrame.
  Qed.
End wp.

(** Proofmode class instances *)
Section proofmode_classes.
  Context `{!melocotonGS_gen hlc val Λ Σ}.
  Implicit Types P Q : iProp Σ.
  Implicit Types Φ : val → iProp Σ.
  Implicit Types v : val.
  Implicit Types e : expr Λ.

  Global Instance frame_wp p s E e R Φ Ψ :
    (∀ v, Frame p R (Φ v) (Ψ v)) →
    Frame p R (WP e @ s; E {{ Φ }}) (WP e @ s; E {{ Ψ }}) | 2.
  Proof. rewrite /Frame=> HR. rewrite wp_frame_l. apply wp_mono, HR. Qed.

  Global Instance is_except_0_wp s E e Φ : IsExcept0 (WP e @ s; E {{ Φ }}).
  Proof. by rewrite /IsExcept0 -{2}fupd_wp -except_0_fupd -fupd_intro. Qed.

  Global Instance elim_modal_bupd_wp p s E e P Φ :
    ElimModal True p false (|==> P) P (WP e @ s; E {{ Φ }}) (WP e @ s; E {{ Φ }}).
  Proof.
    by rewrite /ElimModal intuitionistically_if_elim
      (bupd_fupd E) fupd_frame_r wand_elim_r fupd_wp.
  Qed.

  Global Instance elim_modal_fupd_wp p s E e P Φ :
    ElimModal True p false (|={E}=> P) P (WP e @ s; E {{ Φ }}) (WP e @ s; E {{ Φ }}).
  Proof.
    by rewrite /ElimModal intuitionistically_if_elim
      fupd_frame_r wand_elim_r fupd_wp.
  Qed.
(*
  Global Instance elim_modal_fupd_wp_atomic p s E1 E2 e P Φ :
    ElimModal (Atomic (stuckness_to_atomicity s) e) p false
            (|={E1,E2}=> P) P
            (WP e @ s; E1 {{ Φ }}) (WP e @ s; E2 {{ v, |={E2,E1}=> Φ v }})%I | 100.
  Proof.
    intros ?. by rewrite intuitionistically_if_elim
      fupd_frame_r wand_elim_r wp_atomic.
  Qed.

  Global Instance add_modal_fupd_wp s E e P Φ :
    AddModal (|={E}=> P) P (WP e @ s; E {{ Φ }}).
  Proof. by rewrite /AddModal fupd_frame_r wand_elim_r fupd_wp. Qed.

  Global Instance elim_acc_wp_atomic {X} E1 E2 α β γ e s Φ :
    ElimAcc (X:=X) (Atomic (stuckness_to_atomicity s) e)
            (fupd E1 E2) (fupd E2 E1)
            α β γ (WP e @ s; E1 {{ Φ }})
            (λ x, WP e @ s; E2 {{ v, |={E2}=> β x ∗ (γ x -∗? Φ v) }})%I | 100.
  Proof.
    iIntros (?) "Hinner >Hacc". iDestruct "Hacc" as (x) "[Hα Hclose]".
    iApply (wp_wand with "(Hinner Hα)").
    iIntros (v) ">[Hβ HΦ]". iApply "HΦ". by iApply "Hclose".
  Qed.

  Global Instance elim_acc_wp_nonatomic {X} E α β γ e s Φ :
    ElimAcc (X:=X) True (fupd E E) (fupd E E)
            α β γ (WP e @ s; E {{ Φ }})
            (λ x, WP e @ s; E {{ v, |={E}=> β x ∗ (γ x -∗? Φ v) }})%I.
  Proof.
    iIntros (_) "Hinner >Hacc". iDestruct "Hacc" as (x) "[Hα Hclose]".
    iApply wp_fupd.
    iApply (wp_wand with "(Hinner Hα)").
    iIntros (v) ">[Hβ HΦ]". iApply "HΦ". by iApply "Hclose".
  Qed.*)
End proofmode_classes.

