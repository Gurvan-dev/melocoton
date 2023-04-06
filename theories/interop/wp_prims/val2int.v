From iris.proofmode Require Import proofmode.
From melocoton Require Import named_props stdpp_extra.
From melocoton.mlanguage Require Import mlanguage.
From melocoton.c_interface Require Import defs notation resources.
From melocoton.interop Require Import state lang basics_resources.
From melocoton.interop Require Export prims weakestpre prims_proto.
From melocoton.interop.wp_prims Require Import common.
From melocoton.mlanguage Require Import weakestpre.
Import Wrap.

Section Laws.

Context `{SI: indexT}.
Context {Σ : gFunctors}.
Context `{!heapG_ML Σ, !heapG_C Σ}.
Context `{!invG Σ}.
Context `{!wrapperG Σ}.

Implicit Types P : iProp Σ.
Import mlanguage.

Lemma val2int_correct E e : |- prims_prog e @ E :: val2int_proto.
Proof using.
  iIntros (? ? ? ?) "H". rewrite /mprogwp. iNamed "H".
  do 2 (iExists _; iSplit; first done). iNext.
  rewrite weakestpre.wp_unfold. rewrite /weakestpre.wp_pre.
  iIntros "Hb %σ Hσ". cbn -[prims_prog].
  SI_at_boundary. iNamed "HGC". SI_GC_agree.

  iApply wp_pre_cases_c_prim; [done..|].
  iExists (λ '(e', σ'), e' = WrSE (ExprV #z) ∧ σ' = CState ρc mem).
  iSplit. { iPureIntro. econstructor; eauto. }
  iIntros (? ? ? (? & ?)); simplify_eq.
  do 3 iModIntro.
  iFrame. iSplitL "SIinit". { iExists false. iFrame. }
  iApply wp_value; first done.
  iApply ("Cont" with "[-]").
  do 9 iExists _; rewrite /named; iFrame. eauto.
Qed.

End Laws.