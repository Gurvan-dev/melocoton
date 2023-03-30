From Coq Require Import ssreflect.
From stdpp Require Import strings gmap.
From melocoton Require Import named_props stdpp_extra.
From melocoton.mlanguage Require Import mlanguage.
From melocoton.language Require Import language weakestpre.
From melocoton.mlanguage Require Import weakestpre.
From melocoton.interop Require Import state lang basics_resources.
From transfinite.base_logic.lib Require Import ghost_map ghost_var.
From iris.proofmode Require Import proofmode.
From melocoton.c_interface Require Import defs resources.
From melocoton.ml_lang Require Import lang lang_instantiation primitive_laws.
From melocoton.interop Require Export prims weakestpre prims_proto.
From melocoton.interop Require Import wp_ext_call_laws wp_boundary_laws wp_utils.
Import Wrap.

Section Simulation.

Context `{SI: indexT}.
Context {Σ : gFunctors}.
Context `{!heapG_ML Σ, !heapG_C Σ}.
Context `{!invG Σ}.
Context `{!wrapperG Σ}.

Implicit Types P : iProp Σ.
Import mlanguage.

Lemma wp_to_val (pe : progenv.prog_environ wrap_lang Σ) E v:
    not_at_boundary
 -∗ WP (WrSE (ExprML (ML_lang.Val v))) @ pe; E {{ w,
      ∃ θ' lv, GC θ' ∗ ⌜repr_lval θ' lv w⌝ ∗ lv ~~ v ∗
      at_boundary wrap_lang }}.
Proof using.
  iIntros "Hnb".
  rewrite weakestpre.wp_unfold. rewrite /weakestpre.wp_pre.
  iIntros "%st SI".
  iDestruct (SI_not_at_boundary_is_in_ML with "SI Hnb") as "%H"; destruct H as (ρml & σ & ->).
  iModIntro. iRight. iRight.
  iSplit; first done.

  iAssert (⌜ml_to_c [v] ρml σ (λ ws ρc mem, ml_to_c_core [v] ρml σ ws ρc mem)⌝)%I as "%Hprog".
  { iNamed "SI". iNamed "SIML".
    iDestruct (interp_ML_discarded_locs_pub with "HσML SIAχNone") as "%H". iPureIntro.
    split_and!; eauto. }

  iExists (λ '(e', σ'), ∃ w ρc mem,
    ml_to_c_core [v] ρml σ [w] ρc mem ∧
    e' = WrSE (ExprV w) ∧ σ' = CState ρc mem).
  iSplit. { iPureIntro. eapply ValS; naive_solver. }

  iIntros (? ? (w & ρc & mem & Hcore & -> & ->)).
  iMod (wrap_interp_ml_to_c with "SI Hnb") as "(SI & Hb & HGC & (%lvs & Hsim & %Hrepr))";
    first done.
  do 3 iModIntro. iFrame "SI". iApply weakestpre.wp_value'.
  iDestruct (big_sepL2_cons_inv_l with "Hsim") as "(% & % & -> & Hsim & _)".
  iExists _, _. iFrame. by inversion Hrepr; simplify_eq.
Qed.

Lemma wp_simulates (Ψ : protocol ML_lang.val Σ) E eml emain Φ :
  Ψ on (dom (prims_prog emain)) ⊑ ⊥ → (* Ψ does not use primitive names *)
  not_at_boundary -∗
  WP eml @ ⟨ ∅, Ψ ⟩; E {{ Φ }} -∗
  WP (WrSE (ExprML eml)) @ ⟪ prims_prog emain, wrap_proto Ψ ⟫; E {{ w,
    ∃ θ' lv v, GC θ' ∗ ⌜repr_lval θ' lv w⌝ ∗ lv ~~ v ∗ Φ v ∗
    at_boundary wrap_lang }}.
Proof.
  intros Hnprims.
  iLöb as "IH" forall (eml).
  rewrite weakestpre.wp_unfold. rewrite /weakestpre.wp_pre.
  rewrite wp_unfold. rewrite /wp_pre.
  iIntros "Hnb HWP %st Hst".
  iDestruct (SI_not_at_boundary_is_in_ML with "Hst Hnb") as %(ρml&σ&->).
  iNamed "Hst". iNamed "SIML".
  iDestruct (interp_ML_discarded_locs_pub with "HσML SIAχNone") as %Hpublocs.
  iMod ("HWP" $! σ with "[$HσML]") as "[HWP|[HWP|HWP]]".
  (* value *)
  + iDestruct "HWP" as "(%x & -> & Hσ & Hret)".
    iPoseProof (wp_to_val _ E x with "Hnb") as "Hwp".
    iDestruct (weakestpre.wp_strong_mono_post with "[Hret] Hwp") as "Hwp";
      last first.
    { rewrite weakestpre.wp_unfold. rewrite /weakestpre.wp_pre.
      iApply ("Hwp" $! (MLState ρml σ)). iFrame. by iPureIntro. }
    { cbn. iIntros (v) "(%θ' & %lv & ? & ? & ? & ?)". iExists _, _, _. iFrame. }
  (* extcall *)
  + iDestruct "HWP" as "(%fn_name & %vs & %K' & -> & %Hfn & >(%Ξ & Hσ & HT & Hr))".
    iAssert (⌜¬ is_prim_name fn_name⌝)%I with "[HT]" as "%Hnprim".
    { destruct (decide (is_prim_name fn_name)) as [His|]; last by eauto.
      cbn -[prims_prog]. iDestruct (Hnprims with "[HT]") as "%"; last done.
      rewrite /proto_on. iFrame. iPureIntro. by eapply in_dom_prims_prog. }

    (* take an administrative step in the wrapper *)

    iModIntro. iRight; iRight.
    iSplit; first done.
    iExists (λ '(e', σ'), ∃ ws ρc mem,
      ml_to_c_core vs ρml σ ws ρc mem ∧
      e' = WrE (Wrap.ExprCall fn_name ws) [K'] ∧
      σ' = CState ρc mem).
    iSplit.
    { iPureIntro.
      eapply MakeCallS with (YC := (λ ws ρc mem, ml_to_c_core vs ρml σ ws ρc mem)); eauto.
      { done. }
      { rewrite /= lookup_prims_prog_None //. }
      { split_and!; eauto. }
      { intros. do 3 eexists. split_and!; eauto. } }
    iIntros (? ? (ws & ρc & mem & Hcore & -> & ->)).
    iMod (wrap_interp_ml_to_c with "[- Hnb Hr HT] Hnb") as "(Hσ & Hb & HGC & (%lvs & #Hblk & %))";
      first done.
    { rewrite /wrap_state_interp /ML_state_interp /named.
      iSplitL "Hσ"; first by iFrame. by iFrame. }
    do 3 iModIntro. iFrame "Hσ".

    (* step done; make an external call in the wrapper *)

    rewrite weakestpre.wp_unfold. rewrite /weakestpre.wp_pre.
    iIntros (st') "Hst'".
    iDestruct (SI_at_boundary_is_in_C with "Hst' Hb") as %(ρc'&mem'&->).

    iModIntro. iRight; iLeft. iExists fn_name, ws, [K'].
    iSplit; first done.
    iSplit; first by rewrite /= lookup_prims_prog_None //.
    iFrame "Hb Hst'".
    iExists (λ wret, ∃ θ' vret lvret, GC θ' ∗ Ξ vret ∗ lvret ~~ vret ∗ ⌜repr_lval θ' lvret wret⌝)%I.
    iSplitL "HGC HT".
    { rewrite /wrap_proto /named /=. iExists _, _, _, _.
      iFrame "HGC HT Hblk". iSplit; first done.
      iIntros "!>" (? ? ? ?) "? ? ? %". iExists _, _, _. by iFrame. }
    iNext. iIntros (wret) "((%θ' & %vret & %lvret & HGC & HΞ & Hsim & %) & Hb)".

    (* extcall done; take an administrative step for the call return *)

    rewrite weakestpre.wp_unfold. rewrite /weakestpre.wp_pre.
    iIntros (st') "Hst' !>". clear dependent ρc' mem'.
    iDestruct (SI_at_boundary_is_in_C with "Hst' Hb") as %(ρc'&mem'&->). simpl.
    iRight; iRight. iSplit; first done.

    iDestruct (wrap_interp_c_to_ml with "Hst' HGC Hb [Hsim]") as (ρml' σ' Hc_to_ml) "HH".
    2: by iApply big_sepL2_singleton.
    1: by constructor.
    iExists (λ '(e2, σ2),
      e2 = WrSE (ExprML (language.fill K' (Val vret))) ∧
      σ2 = MLState ρml' σ').
    iSplit. { iPureIntro. eapply RetS; eauto. }
    iIntros (? ? (-> & ->)). iMod "HH" as "[Hst' Hnb]".
    do 3 iModIntro. iFrame "Hst'".

    (* continue execution using IH *)

    iApply ("IH" with "Hnb"). by iApply "Hr".

  (* step *)
  + iDestruct "HWP" as "(%Hred & HWP)".
    iModIntro. iRight. iRight. iSplit; first done.
    iExists (λ '(e2, σ2), ∃ eml' σ',
      language.language.prim_step ∅ eml σ eml' σ' ∧
      e2 = WrSE (ExprML eml') ∧ σ2 = MLState ρml σ').
    iSplit.
    { iPureIntro. eapply StepMLS; eauto.
      by eapply reducible_not_val. }
    iIntros (? ? (e' & σ' & Hstep & -> & ->)).
    iMod ("HWP" $! _ _ Hstep) as "HWP".
    do 2 iModIntro. iMod "HWP" as "(HσC & HWP')".
    iModIntro. iSplitR "HWP' Hnb".
    { rewrite /weakestpre.state_interp /= /named.
      iSplitL "HσC"; by iFrame. }
    iApply ("IH" with "Hnb HWP'").
Qed.

Lemma callback_proto_refines E emain Ψ :
  Ψ on (dom (prims_prog emain)) ⊑ ⊥ →
  callback_proto E Ψ ⊑ mprog_proto E (prims_prog emain) (wrap_proto Ψ).
Proof using.
  iIntros (Hnprim ? ? ?) "Hproto". unfold weakestpre.prog_proto. iNamed "Hproto".
  iExists _. iSplit; first done. iIntros "!> Hb".
  rewrite weakestpre.wp_unfold. rewrite /weakestpre.wp_pre.
  iIntros (st) "Hst".
  iDestruct (SI_at_boundary_is_in_C with "Hst Hb") as %(ρc&mem&->). simpl.
  iAssert (⌜θ = θC ρc ∧
            gmap_inj (θC ρc) ∧
            ζC ρc !! γ = Some (Bclosure f x e)⌝)%I
    as %(-> & Hθinj & Hγ).
  { iNamed "Hst". iNamed "HGC". iNamed "SIC". SI_GC_agree.
    iDestruct (lstore_own_immut_of with "[$] Hclos") as %(Hγvirt & _).
    iPureIntro. split; eauto. split; first by apply HGCOK.
    eapply freeze_lstore_lookup_bclosure; first done.
    eapply lookup_union_Some_r; eauto. }

  iDestruct "Hclos" as "#Hclos".
  iDestruct (wrap_interp_c_to_ml [w;w'] _ _ _ [RecV f x e; v']
    with "Hst HGC Hb [Hclos Hsim']") as (ρml' σ' Hc_to_ml) "HH".
  { repeat constructor; eauto. }
  { iApply big_sepL2_cons. iSplit.
    { cbn. iExists _. by iFrame "Hclos". }
    { iApply big_sepL2_cons; iFrame. by iApply big_sepL2_nil. } }

  iModIntro.
  iRight; iRight. iSplit; first done.
  iExists (λ '(e2, σ2),
    e2 = WrSE (ExprML (App (Val (RecV f x e)) (Val v'))) ∧
    σ2 = MLState ρml' σ').
  iSplit. { iPureIntro. eapply CallbackS; eauto. }
  iIntros (? ? (-> & ->)). iMod "HH" as "(Hst & Hnb)".
  do 3 iModIntro. iFrame "Hst".
  iApply (weakestpre.wp_wand with "[-Cont Hclos]").
  { by iApply (wp_simulates with "Hnb [WPcallback]"). }
  cbn. iIntros (v) "(%θ' & %lv & %vret & HGC & % & Hsim & Hψ & $)".
  iApply ("Cont" with "[$] [$] [$]"); eauto.
Qed.

Lemma main_proto_refines E emain Ψ :
  Ψ on (dom (prims_prog emain)) ⊑ ⊥ →
  main_proto E emain Ψ ⊑ mprog_proto E (prims_prog emain) (wrap_proto Ψ).
Proof using.
  iIntros (Hnprim ? ? ?) "Hproto". unfold weakestpre.prog_proto. iNamed "Hproto".
  iExists _. iSplit; first done. iIntros "!> Hb".
  rewrite weakestpre.wp_unfold. rewrite /weakestpre.wp_pre.
  iIntros (st) "Hst".
  iDestruct (SI_at_boundary_is_in_C with "Hst Hb") as %(ρc&mem&->). simpl.
  iNamed "Hst". iNamed "SIC". unfold gctoken.at_init.
  iDestruct (ghost_var_agree with "Hat_init SIinit") as %?; simplify_eq.
  iNamed "Hinit". iRename "Hat_init" into "GCinit".
  destruct ρc. cbn [state.ζC state.χC state.θC state.rootsC] in *. SI_GC_agree.
  iAssert (ghost_var wrapperG_γat_init 1 true) with "[GCinit SIinit]" as "SIinit".
  { rewrite -{3}Qp.half_half.
    iApply (fractional.fractional_merge _ _ (λ q, ghost_var wrapperG_γat_init q true)
             with "GCinit SIinit"). }
  iMod (ghost_var_update false with "SIinit") as "SIinit".
  iMod (ghost_var_update_halves false with "Hb SIbound") as "[Hb SIbound]".

  iModIntro.
  iRight; iRight. iSplit; first done.
  iExists (λ '(e2, σ2),
    e2 = WrSE (ExprML emain) ∧
    σ2 = MLState {| χML := ∅; ζML := ∅; rootsML := ∅ |} ∅).
  iSplit. { iPureIntro. eapply MainS; eauto. }
  iIntros (? ? (-> & ->)).
  do 3 iModIntro.
  rewrite /weakestpre.state_interp /= /named.
  rewrite /ML_state_interp /= /named.
  rewrite /public_state_interp.
  rewrite !fmap_empty !right_id_L !dom_empty_L. iFrame.
  rewrite pub_locs_in_lstore_empty big_sepM_empty dom_empty_L. iFrame.
  rewrite big_sepS_empty. iSplit; first by iPureIntro.

  iApply (weakestpre.wp_wand with "[-Cont]").
  { by iApply (wp_simulates with "Hb WPmain"). }
  cbn. iIntros (v) "(%θ' & %lv & %vret & HGC & %Hrepr & Hsim & HΦ' & $)".
  by iApply ("Cont" with "HGC HΦ' Hsim").
Qed.

Lemma wrap_refines E e Ψ :
  Ψ on (dom (wrap_prog e)) ⊑ ⊥ →
  prims_proto E e Ψ ⊑ mprog_proto E (wrap_prog e) (wrap_proto Ψ).
Proof using.
  intros Hnprim.
  iIntros (? ? ?) "H". iDestruct "H" as (p Hp) "H".
  destruct p; try by iApply (base_prim_proto_refines with "H").
  { by iApply (callback_proto_refines with "H"). }
  { iAssert (⌜e = e0⌝)%I as %->.
    { iNamed "H". iClear "∗". vm_compute in Hp. by simplify_eq. }
    by iApply (main_proto_refines with "H"). }
Qed.

End Simulation.
