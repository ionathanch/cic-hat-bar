{-#LANGUAGE RankNTypes #-}

module Inference.Infer
    ( infer
    ) where

import Grammar.All
import Inference.Auxil
import Inference.Defs
import Data.List (foldl')
import Control.Exception (assert)

{- Inference algorithm 
Check and Infer as described by CIC^ Figure 3
RecCheck as described by F^ Section 3.4
-}

-- (V, Δ, Γ, e°, T) -> (V, C, e)
check :: StageVars -> IndTypes -> Context -> Term Bare -> Term Stage -> (StageVars, Constraints, Term Stage)
check v d g eBare t =
    let (ve, ce, e, te) = infer v d g eBare
    in  (ve, ce ++ te ⪯ t, e)

-- (V, Δ, Γ, e°) -> (V, C, e, T)
infer :: StageVars -> IndTypes -> Context -> Term Bare -> (StageVars, Constraints, Term Stage, Term Stage)
infer v d _ Prop     = (v, [], Prop,   Type 1)
infer v d _ Set      = (v, [], Set,    Type 1)
infer v d _ (Type i) = (v, [], Type i, Type (i + 1))
infer v d g (Var x)  = (v, [], Var x,  getType x g)
infer v d g (Abs x t eBare) =
    let (v1, c1, t1, w1) = infer v d g t
        (ve, ce, e,  t2) = infer v1 d (Beta x t1 : g) eBare
        a = assert (isSort (whnf w1)) Nothing
    in  (ve, c1 ++ ce, Abs x t e, Prod x t1 t2)
infer v d g (Prod x t1Bare t2Bare) =
    let (v1, c1, t1, w1) = infer v d g t1Bare
        (v2, c2, t2, w2) = infer v1 d (Beta x t1 : g) t2Bare
    in  (v2, c1 ++ c2, Prod x t1 t2, rules (whnf w1) (whnf w2))
infer v d g (App e1Bare e2Bare) =
    let (v1, c1, e1, t1) = infer v d g e1Bare
        Prod x t2 t = whnf t1
        (v2, c2, e2) = check v1 d g e2Bare t2
    in  (v2, c1 ++ c2, App e1 e2, bind t x e2)
infer v d g (Let x e1Bare t e2Bare) =
    let (vt, ct, t1, wt) = infer v d g t
        (v1, c1, e1) = check vt d g e1Bare t1
        (v2, c2, e2, t2) = infer v1 d (Zeta x e1 t1 : g) e2Bare
        a = assert (isSort (whnf wt)) Nothing
    in  (v2, ct ++ c1 ++ c2, Let x e1 t e2, bind t2 x e1)
infer v d g (Ind i Bare params args) =
    let ti = typeInd i d
        a1 = assert (lengthOfIndParams i d == length params) Nothing
        a2 = assert (lengthOfIndArgs   i d == length args)   Nothing
        fv = getFreeVariable g (params ++ args)
        (vi, c, e, t) = infer v d (Beta fv ti : g) (apply (Var fv) params args)
        (_, paramsSized, argsSized) = unapply e (length args)
    in  (incStageVars vi, c, Ind i (nextStage vi) paramsSized argsSized, t)
infer v d g (Constr x params args) =
    let tc = typeConstr x (nextStage v) d
        a1 = assert (lengthOfConstrParams x d == length params) Nothing
        a2 = assert (lengthOfConstrArgs   x d == length args)   Nothing
        fv = getFreeVariable g (params ++ args)
        (vc, c, e, t) = infer (incStageVars v) d (Beta fv tc : g) (apply (Var fv) params args)
        (_, _, argsSized) = unapply e (length args)
    in  (vc, c, Constr x params argsSized, t)
infer v d g (Case ecBare pBare esBare) =
    let s  = nextStage vc
        (vc, cc, ec, tc) = infer v d g ecBare
        Ind i r params args = whnf tc
        a1 = assert (lengthOfIndParams i d == length params)
        (vp, cp,  p, tp) = infer (incStageVars vc) d g pBare
        Prod xn tn tpn = prodBody (lengthOfIndArgs i d) tp
        w' = whnf tpn
        a2 = assert (elim (getIndSort i d) w') Nothing
        c0 = Constraint r (Succ s) : tp ⪯ typePred i s params xn w' d
        (v, c, es) = foldl' (checkBranch s p params) (vp, c0, []) (zip (getConstrNames i d) esBare)
    in  (v, c ++ cp ++ cc, Case ec pBare es, apply p args [ec])
    where
        prodBody :: Int -> Term Stage -> Term Stage
        prodBody 0 t = whnf t
        prodBody n t =
            let Prod xi ti tpi = whnf t
            in  prodBody (n - 1) tpi
        checkBranch :: Stage -> Term Stage -> [Term Stage] -> (StageVars, Constraints, [Term Stage])
                    -> (String, Term Bare) -> (StageVars, Constraints, [Term Stage])
        checkBranch s p params (v, c, es) (constr, eBare) =
            let (vi, ci, e) = check v d g eBare (typeBranch constr s p params d)
            in  (vi, ci ++ c, es ++ [e])
infer v _ _ _ = (v, [], Type 1, Type 2)

-- (α, V*, V≠, C') -> C
recCheck :: Stage -> StageVars -> StageVars -> Constraints -> Constraints
recCheck s vstar vneq c = c
