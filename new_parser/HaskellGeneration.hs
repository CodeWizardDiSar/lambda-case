{-# LANGUAGE LambdaCase, TypeSynonymInstances, FlexibleInstances #-}

module HaskellGeneration where

import ASTTypes

-- helpers
show_maybe :: ToHaskell a => Maybe a -> String
show_maybe = \case
  Nothing -> ""
  Just a -> to_haskell a

show_list :: ToHaskell a => [a] -> String
show_list = concatMap to_haskell

show_list_sep :: ToHaskell a => String -> [a] -> String
show_list_sep = \sep -> concatMap ((sep ++) . to_haskell)

show_list_comma :: ToHaskell a => [a] -> String
show_list_comma = show_list_sep ", "

show_pair_list :: (ToHaskell a, ToHaskell b) => [(a, b)] -> String
show_pair_list = concatMap (\(a, b) -> to_haskell a ++ to_haskell b)

class ToHaskell a where
  to_haskell :: a -> String

-- Values: Literal, Identifier, ParenExpr, Tuple, List, ParenFuncApp
instance ToHaskell Literal where 
  to_haskell = \case
    Int i -> show i
    R r -> show r
    Ch c -> show c
    S s -> show s

instance ToHaskell Identifier where
  to_haskell = \(Id s) -> s

instance ToHaskell ParenExpr where
  to_haskell = \(PE pei) -> "(" ++ to_haskell pei ++ ")"

instance ToHaskell InsideParenExpr where
  to_haskell = \case
    LOE1 soe -> to_haskell soe
    LFE1 sfe -> to_haskell sfe

instance ToHaskell Tuple where
  to_haskell = \(T (loue, loues)) ->
    "(" ++ to_haskell loue ++ ", " ++ to_haskell loues ++ ")"

instance ToHaskell LineExprOrUnders where
  to_haskell = \(LOUEs (loue, loues)) ->
    to_haskell loue ++ show_list_comma loues

instance ToHaskell LineExprOrUnder where
  to_haskell = \case
    LE1 le -> to_haskell le
    Underscore1 -> "_"

instance ToHaskell LineExpr where
  to_haskell = \case
    BOAE1 npoa -> to_haskell npoa
    LOE2 soe -> to_haskell soe
    LFE2 sfe -> to_haskell sfe

instance ToHaskell BasicOrAppExpr where
  to_haskell = \case
    BE3 be -> to_haskell be
    PrFA1 prfa -> to_haskell prfa
    PoFA1 pofa -> to_haskell pofa

instance ToHaskell BasicExpr where
  to_haskell = \case
    Lit1 lit -> to_haskell lit
    Id1 id -> to_haskell id
    T1 tuple -> to_haskell tuple
    L1 list -> to_haskell list
    PFA pfa -> to_haskell pfa
    SI1 sid -> to_haskell sid

instance ToHaskell BigTuple where
  to_haskell = \(BT (loue, loues, loues_l)) ->
    "( " ++ to_haskell loue ++ ", " ++ to_haskell loues ++
    show_list_sep "\n, " loues_l ++ "\n)"

instance ToHaskell List where
  to_haskell = \(L maybe_loues) -> "[" ++ show_maybe maybe_loues ++ "]"

instance ToHaskell BigList where
  to_haskell = \(BL (loues, loues_l)) ->
    "[ " ++ to_haskell loues ++ show_list_sep "\n, " loues_l ++ "\n]"

instance ToHaskell ParenFuncApp where
  to_haskell = \case
    IWA1 (maybe_args1, id_with_args, maybe_args2) ->
      show_maybe maybe_args1 ++ to_haskell id_with_args ++
      show_maybe maybe_args2
    AI (args, id, maybe_args) ->
      to_haskell args ++ to_haskell id ++ show_maybe maybe_args
    IA (id, args) ->
      to_haskell id ++ to_haskell args

instance ToHaskell Arguments where
  to_haskell = \(As loues) -> "(" ++ to_haskell loues ++ ")"

instance ToHaskell IdentWithArgs where
  to_haskell =
    \(IWA
      (id_with_args_start, args, str, empty_par_or_args_str_pairs, maybe_ch)
     ) ->
    to_haskell id_with_args_start ++ to_haskell args ++ str ++
    concatMap show_pair empty_par_or_args_str_pairs ++ show_maybe_char maybe_ch
    where
    show_pair :: (EmptyParenOrArgs, String) -> String
    show_pair = \(epoa, str) -> to_haskell epoa ++ str

    show_maybe_char :: Maybe Char -> String
    show_maybe_char = \case
      Nothing -> ""
      Just c -> [c]

instance ToHaskell IdentWithArgsStart where
  to_haskell = \(IWAS str) -> str

instance ToHaskell EmptyParenOrArgs where
  to_haskell = \case
    EmptyParen -> "()"
    As1 args -> to_haskell args

-- Values: PreFunc, PostFunc, BasicExpr, Change
instance ToHaskell PreFunc where
  to_haskell = \(PF id) -> to_haskell id ++ ":"

instance ToHaskell PreFuncApp where
  to_haskell = \(PrFA (pf, oper)) -> to_haskell pf ++ to_haskell oper

instance ToHaskell PostFunc where
  to_haskell = \case
    Id2 id -> "." ++ to_haskell id
    SI2 sid -> "." ++ to_haskell sid
    C1 c -> "." ++ to_haskell c

instance ToHaskell SpecialId where
  to_haskell = \case
    First -> "1st"
    Second -> "2nd"
    Third -> "3rd"
    Fourth -> "4th"
    Fifth -> "5th"

instance ToHaskell PostFuncApp where
  to_haskell = \(PoFA (pfa, pfs)) -> to_haskell pfa ++ show_list pfs

instance ToHaskell PostFuncArg where
  to_haskell = \case
    PE2 pe -> to_haskell pe
    BE2 be -> to_haskell be
    Underscore2 -> "_"

instance ToHaskell Change where
  to_haskell = \(C (fc, fcs)) ->
    "change{" ++ to_haskell fc ++ show_list_comma fcs ++ "}"

instance ToHaskell FieldChange where
  to_haskell = \(FC (f, le)) -> to_haskell f ++ " = " ++ to_haskell le

instance ToHaskell Field where
  to_haskell = \case
    Id3 id -> to_haskell id
    SI3 sid -> to_haskell sid

-- Values: OpExpr
instance ToHaskell OpExpr where
  to_haskell = \case
    LOE3 soe -> to_haskell soe
    BOE1 boe -> to_haskell boe

instance ToHaskell OpExprStart where
  to_haskell = \(OES oper_op_pairs) -> show_pair_list oper_op_pairs

instance ToHaskell LineOpExpr where
  to_haskell = \(LOE (oes, loee)) -> to_haskell oes ++ to_haskell loee

instance ToHaskell LineOpExprEnd where
  to_haskell = \case
    OA1 oa -> to_haskell oa
    LFE3 sfe -> to_haskell sfe

instance ToHaskell BigOpExpr where
  to_haskell = \case
    BOEOS1 boeos -> to_haskell boeos
    BOEFS1 boefs -> to_haskell boefs

instance ToHaskell BigOpExprOpSplit where
  to_haskell = \(BOEOS (osls, maybe_oes, ose)) ->
    show_list osls ++ show_maybe maybe_oes ++ to_haskell ose

instance ToHaskell OpSplitLine where
  to_haskell = \(OSL (oes, maybe_op_arg_comp_op)) ->
    to_haskell oes ++ show_moaco maybe_op_arg_comp_op ++ "  "
    where
    show_moaco :: Maybe (Operand, FuncCompOp) -> String
    show_moaco = \case
      Nothing -> "\n"
      Just (op_arg, comp_op) ->
        to_haskell op_arg ++ " " ++  to_haskell comp_op ++ "\n"

instance ToHaskell OpSplitEnd where
  to_haskell = \case
    OA2 oa -> to_haskell oa
    FE1 fe -> to_haskell fe

instance ToHaskell BigOpExprFuncSplit where
  to_haskell = \(BOEFS (oes, boefs)) -> to_haskell oes ++ to_haskell boefs

instance ToHaskell BigOrCasesFuncExpr where
  to_haskell = \case
    BFE1 bfe -> to_haskell bfe
    CFE1 cfe -> to_haskell cfe
  
instance ToHaskell Operand where
  to_haskell = \case
    BOAE2 npoa -> to_haskell npoa
    PE3 pe -> to_haskell pe
    Underscore3 -> "_"

instance ToHaskell Op where
  to_haskell = \case
    FCO3 co -> " " ++ to_haskell co ++ " "
    OSO oso -> " " ++ to_haskell oso ++ " "

instance ToHaskell FuncCompOp where
  to_haskell = \case
    RightComp -> "o>"
    LeftComp -> "<o"

instance ToHaskell OptionalSpacesOp where
  to_haskell = \case
    RightApp -> "->"
    LeftApp -> "<-"
    Power -> "^" 
    Mult -> "*" 
    Div -> "/" 
    Plus -> "+" 
    Minus -> "-" 
    Equal -> "==" 
    NotEqual -> "/="
    Greater -> ">" 
    Less -> "<" 
    GrEq -> ">="
    LeEq -> "<="
    And -> "&" 
    Or -> "|" 
    Use -> ";>"
    Then -> ";" 

-- Values: FuncExpr
instance ToHaskell FuncExpr where
  to_haskell = \case
    LFE4 sfe -> to_haskell sfe
    BFE2 bfe -> to_haskell bfe
    CFE2 cfe -> to_haskell cfe

instance ToHaskell LineFuncExpr where
  to_haskell = \(LFE (params, lfb)) ->
    to_haskell params ++ " =>" ++ to_haskell lfb

instance ToHaskell BigFuncExpr where
  to_haskell = \(BFE (params, bfb)) ->
    to_haskell params ++ " =>" ++ to_haskell bfb

instance ToHaskell Parameters where
  to_haskell = \case
    ParamId id -> to_haskell id
    Star1 -> "*"
    Params (params, params_l) ->
      "(" ++ to_haskell params ++ show_list_comma params_l ++ ")"

instance ToHaskell LineFuncBody where
  to_haskell = \case
    BOAE3 npoa -> " " ++ to_haskell npoa
    LOE4 soe -> " " ++ to_haskell soe

instance ToHaskell BigFuncBody where
  to_haskell = \case
    BOAE4 npoa -> "\n" ++ to_haskell npoa
    OE1 oe -> "\n" ++ to_haskell oe

instance ToHaskell CasesFuncExpr where
  to_haskell = \(CFE (cps, cs, maybe_ec)) ->
    to_haskell cps ++ show_list cs ++ show_maybe maybe_ec

instance ToHaskell CasesParams where
  to_haskell = \case
    CParamId id -> to_haskell id
    CasesKeyword -> "cases"
    Star2 -> "*"
    CParams (cps, cps_l) ->
      "(" ++ to_haskell cps ++ show_list_comma cps_l ++ ")"

instance ToHaskell Case where
  to_haskell = \(Ca (m, cb)) -> "\n" ++ to_haskell m ++ " =>" ++ to_haskell cb

instance ToHaskell EndCase where
  to_haskell = \(EC cb) -> "\n... =>" ++ to_haskell cb

instance ToHaskell Matching where
  to_haskell = \case
    Lit2 lit -> to_haskell lit
    Id5 id -> to_haskell id
    PFM (pf, mos) -> to_haskell pf ++ to_haskell mos
    TM1 tm -> to_haskell tm
    LM1 lm -> to_haskell lm

instance ToHaskell MatchingOrStar where
  to_haskell = \case
    M1 m -> to_haskell m
    Star -> "*"

instance ToHaskell TupleMatching where
  to_haskell = \(TM (mos, mos_l)) ->
    "(" ++ to_haskell mos ++ show_list_comma mos_l ++ ")"

instance ToHaskell ListMatching where
  to_haskell = \(LM maybe_m_ms) -> case maybe_m_ms of
    Nothing -> "[]"
    Just (mos, mos_l) -> "[" ++ to_haskell mos ++ show_list_comma mos_l ++ "]"

instance ToHaskell CaseBody where
  to_haskell = \(CB (cbs, maybe_we)) -> to_haskell cbs ++ show_maybe maybe_we

instance ToHaskell CaseBodyStart where
  to_haskell = \case
    LFB1 lfb -> to_haskell lfb
    BFB1 bfb -> to_haskell bfb

-- Values: ValueDef, GroupedValueDefs, WhereExpr
instance ToHaskell ValueDef where
  to_haskell = \(VD (id, t, ve, maybe_we)) ->
    to_haskell id ++ "\n  : " ++ to_haskell t ++ "\n  = " ++ to_haskell ve ++
    show_maybe maybe_we

instance ToHaskell ValueExpr where
  to_haskell = \case
    BOAE5 npoa -> to_haskell npoa
    OE2 oe -> to_haskell oe
    FE2 fe -> to_haskell fe
    BT1 bt -> to_haskell bt
    BL1 bl -> to_haskell bl

instance ToHaskell GroupedValueDefs where
  to_haskell = \(GVDs (id, ids, ts, csles, csles_l)) ->
    to_haskell id ++ show_list_comma ids ++
    "\n  : " ++ to_haskell ts ++
    "\n  = " ++ to_haskell csles ++ show_list_sep "\n  , " csles_l

instance ToHaskell Types where
  to_haskell = \case
    Ts (t, ts) -> to_haskell t ++ show_list_comma ts
    All t -> "all " ++ to_haskell t

instance ToHaskell LineExprs where
  to_haskell = \(CSLE (le, les)) -> to_haskell le ++ show_list_comma les

instance ToHaskell WhereExpr where
  to_haskell = \(WE (wde, wdes)) ->
    "\nwhere\n" ++ to_haskell wde ++ show_list_sep "\n\n" wdes

instance ToHaskell WhereDefExpr where
  to_haskell = \case
    VD1 vd -> to_haskell vd
    GVDs1 gvd -> to_haskell gvd

-- Type
instance ToHaskell Type where
  to_haskell = \(Ty (maybe_c, st)) -> show_maybe maybe_c ++ to_haskell st

instance ToHaskell SimpleType where
  to_haskell = \case
    TIOV1 tiov -> to_haskell tiov
    TA1 ta -> to_haskell ta
    PoT1 pt -> to_haskell pt
    PT1 pt -> to_haskell pt
    FT1 ft -> to_haskell ft

instance ToHaskell TypeIdOrVar where
  to_haskell = \case
    TId1 tid -> to_haskell tid
    TV1 tv -> to_haskell tv

instance ToHaskell TypeId where
  to_haskell = \(TId str) -> str

instance ToHaskell TypeVar where
  to_haskell = \case
    PTV1 ptv -> to_haskell ptv
    AHTV1 ahtv -> to_haskell ahtv

instance ToHaskell ParamTVar where
  to_haskell = \(PTV i) -> "T" ++ show i

instance ToHaskell AdHocTVar where
  to_haskell = \(AHTV c) -> "@" ++ [c]

instance ToHaskell TypeApp where
  to_haskell = \case
    TIWA1 (maybe_tip1, tiwa, maybe_tip2) ->
      show_maybe maybe_tip1 ++ to_haskell tiwa ++ show_maybe maybe_tip2
    TIPTI (tip, tid_or_tv, maybe_tip) ->
      to_haskell tip ++ to_haskell tid_or_tv ++ show_maybe maybe_tip
    TITIP (tid_or_tv, tip) ->
      to_haskell tid_or_tv ++ to_haskell tip

instance ToHaskell TypeIdWithArgs where
  to_haskell = \(TIWA (tid, tip_str_pairs)) ->
    to_haskell tid ++
    concatMap (\(tip, str) -> to_haskell tip ++ str) tip_str_pairs

instance ToHaskell TIdOrAdHocTVar where
  to_haskell = \case
    TId4 tid -> to_haskell tid
    AHTV2 ahtv -> to_haskell ahtv

instance ToHaskell TypesInParen where
  to_haskell = \(TIP (st, sts)) ->
    "(" ++ to_haskell st ++ show_list_comma sts ++ ")"

instance ToHaskell ProdType where
  to_haskell = \(PT (fopt, fopts)) ->
    to_haskell fopt ++ show_list_sep " x " fopts

instance ToHaskell FieldType where
  to_haskell = \case
    PBT1 ft -> to_haskell ft
    PoT3 pt -> to_haskell pt

instance ToHaskell PowerBaseType where
  to_haskell = \case
    TIOV3 tiov -> to_haskell tiov
    TA3 ta -> to_haskell ta
    IPT ipt -> to_haskell ipt

instance ToHaskell InParenT where
  to_haskell = \case
    PT3 pt -> "(" ++ to_haskell pt ++ ")"
    FT3 ft -> "(" ++ to_haskell ft ++ ")"  

instance ToHaskell PowerType where
  to_haskell = \(PoT (ft, i)) -> to_haskell ft ++ "^" ++ show i

instance ToHaskell FuncType where
  to_haskell = \(FT (it, ot)) -> to_haskell it ++ " => " ++ to_haskell ot

instance ToHaskell InOrOutType where
  to_haskell = \case
    TIOV2 tiov -> to_haskell tiov
    TA2 ta -> to_haskell ta
    PoT2 pt -> to_haskell pt
    PT2 pt -> to_haskell pt
    FT2 ft -> "(" ++ to_haskell ft ++ ")"

instance ToHaskell Condition where
  to_haskell = \(Co pn) -> to_haskell pn ++ " ==> "

-- TypeDef, TypeNickname
instance ToHaskell TypeDef where
  to_haskell = \case
    TTD1 ttd -> to_haskell ttd
    OTD1 otd -> to_haskell otd

instance ToHaskell TupleTypeDef where
  to_haskell = \(TTD (tn, pcsis, ttde)) ->
    "tuple_type " ++ to_haskell tn ++ "\nvalue\n  " ++ to_haskell pcsis ++
    " : " ++ to_haskell ttde

instance ToHaskell ProdOrPowerType where
  to_haskell = \case
    PT4 pt -> to_haskell pt
    PoT4 pt -> to_haskell pt

instance ToHaskell TypeName where
  to_haskell = \(TN (maybe_pvip1, tid, pvip_str_pairs, maybe_pvip2)) ->
    show_maybe maybe_pvip1 ++ to_haskell tid ++
    concatMap (\(pvip, str) -> to_haskell pvip ++ str) pvip_str_pairs ++
    show_maybe maybe_pvip2

instance ToHaskell ParamVarsInParen where
  to_haskell = \(PVIP (ptv, ptvs)) ->
    "(" ++ to_haskell ptv ++ show_list_comma ptvs ++ ")"

instance ToHaskell IdTuple where
  to_haskell = \(PCSIs (id, ids)) ->
    "(" ++ to_haskell id ++ show_list_comma ids ++ ")"

instance ToHaskell OrTypeDef where
  to_haskell =
    \(OTD (tn, id, mst, id_mst_pairs)) ->
    "or_type " ++ to_haskell tn ++
    "\nvalues\n  " ++ to_haskell id ++ show_mst mst ++
    concatMap show_id_mst_pair id_mst_pairs
    where
    show_mst :: Maybe SimpleType -> String
    show_mst = \case
      Nothing -> ""
      Just st -> ":" ++ to_haskell st

    show_id_mst_pair :: (Identifier, Maybe SimpleType) -> String
    show_id_mst_pair = \(id, mst) -> " | " ++ to_haskell id ++ show_mst mst

instance ToHaskell TypeNickname where
  to_haskell = \(TNN (tn, st)) ->
    "type_nickname " ++ to_haskell tn ++ " = " ++ to_haskell st

-- TypePropDef
instance ToHaskell TypePropDef where
  to_haskell = \case
    APD1 apd -> to_haskell apd
    RPD1 rpd -> to_haskell rpd

instance ToHaskell AtomPropDef where
  to_haskell = \(APD (pnl, id, st)) ->
    to_haskell pnl ++ "\nvalue\n  " ++ to_haskell id ++ " : " ++ to_haskell st

instance ToHaskell RenamingPropDef where
  to_haskell = \(RPD (pnl, pn, pns)) ->
    to_haskell pnl ++ "\nequivalent\n  " ++ to_haskell pn ++
    show_list_comma pns

instance ToHaskell PropNameLine where
  to_haskell = \(PNL pn) -> "type_proposition " ++ to_haskell pn

instance ToHaskell PropName where
  to_haskell = \case
    NPStart1 (c, np_ahvip_pairs, maybe_np) ->
      [c] ++ show_pair_list np_ahvip_pairs ++ show_maybe maybe_np
    AHVIPStart1 (ahvip_np_pairs, maybe_ahvip) ->
      show_pair_list ahvip_np_pairs ++ show_maybe maybe_ahvip

instance ToHaskell AdHocVarsInParen where
  to_haskell = \(AHVIP (ahtv, ahtvs)) ->
    "(" ++ to_haskell ahtv ++ show_list_comma ahtvs ++ ")"

instance ToHaskell NamePart where
  to_haskell = \(NP str) -> str

-- TypeTheo 
instance ToHaskell TypeTheo where
  to_haskell = \(TT (pnws, maybe_pnws, proof)) ->
    "type_theorem " ++ to_haskell pnws ++ show_mpnws maybe_pnws ++
    "\nproof" ++ to_haskell proof
    where
    show_mpnws :: Maybe PropNameWithSubs -> String
    show_mpnws = \case
      Nothing -> ""
      Just pnws -> " => " ++ to_haskell pnws

instance ToHaskell PropNameWithSubs where
  to_haskell = \case
    NPStart2 (c, np_sip_pairs, maybe_np) ->
      [c] ++ show_pair_list np_sip_pairs ++ show_maybe maybe_np
    SIPStart (sip_np_pairs, maybe_sip) ->
      show_pair_list sip_np_pairs ++ show_maybe maybe_sip

instance ToHaskell SubsInParen where
  to_haskell = \(SIP (tvs, tvss)) ->
    "(" ++ to_haskell tvs ++ show_list_comma tvss ++ ")"

instance ToHaskell TVarSub where
  to_haskell = \case
    TIOV4 tiov -> to_haskell tiov
    TAS1 tas -> to_haskell tas
    PoTS1 pts -> to_haskell pts
    PTS1 pts -> to_haskell pts
    FTS1 fts -> to_haskell fts

instance ToHaskell TypeAppSub where
  to_haskell = \case
    TIWS1 (maybe_souip1, tiws, maybe_souip2) ->
      show_maybe maybe_souip1 ++ to_haskell tiws ++ show_maybe maybe_souip2
    SOUIP_TI (souip, tid_or_tv, maybe_souip) ->
      to_haskell souip ++ to_haskell tid_or_tv ++ show_maybe maybe_souip
    TI_SOUIP (tid_or_tv, souip) ->
      to_haskell tid_or_tv ++ to_haskell souip

instance ToHaskell TypeIdWithSubs where
  to_haskell = \(TIWS (tid, souip_str_pairs)) ->
    to_haskell tid ++
    concatMap (\(souip, str) -> to_haskell souip ++ str) souip_str_pairs

instance ToHaskell SubsOrUndersInParen where
  to_haskell = \(SOUIP (sou, sous)) ->
    "(" ++ to_haskell sou ++ show_list_comma sous ++ ")"

instance ToHaskell SubOrUnder where
  to_haskell = \case
    TVS1 tvs -> to_haskell tvs
    Underscore4 -> "_"

instance ToHaskell PowerTypeSub where
  to_haskell = \(PoTS (pbts, i)) -> to_haskell pbts ++ "^" ++ show i

instance ToHaskell PowerBaseTypeSub where
  to_haskell = \case
    Underscore5 -> "_"
    TIOV5 tid_or_var -> to_haskell tid_or_var
    TAS2 tas -> to_haskell tas
    IPTS1 ipts -> "(" ++ to_haskell ipts ++ ")"

instance ToHaskell InParenTSub where
  to_haskell = \case
    PTS2 pts -> to_haskell pts
    FTS2 fts -> to_haskell fts

instance ToHaskell ProdTypeSub where
  to_haskell = \(PTS (fts, fts_l)) ->
    to_haskell fts ++ show_list_sep " x " fts_l

instance ToHaskell FieldTypeSub where
  to_haskell = \case
    PBTS1 pbts -> to_haskell pbts
    PoTS2 pots -> to_haskell pots

instance ToHaskell FuncTypeSub where
  to_haskell = \(FTS (ioots1, ioots2)) ->
    to_haskell ioots1 ++ " => " ++ to_haskell ioots2 

instance ToHaskell InOrOutTypeSub where
  to_haskell = \case
    Underscore6 -> "_"
    TIOV6 tiov -> to_haskell tiov
    TAS3 tas -> to_haskell tas
    PoTS3 pots -> to_haskell pots
    PTS3 pts -> to_haskell pts
    FTS3 fts -> to_haskell fts

instance ToHaskell Proof where
  to_haskell = \case
    P1 (iooe, le) -> " " ++ to_haskell iooe ++ " " ++ to_haskell le
    P2 (iooe, ttve) -> "\n  " ++ to_haskell iooe ++ to_haskell ttve

instance ToHaskell IdOrOpEq where
  to_haskell = \(IOOE (id, maybe_op_id)) ->
    to_haskell id ++ show_moi maybe_op_id ++ " ="
    where
    show_moi :: Maybe (Op, Identifier) -> String
    show_moi = \case
      Nothing -> ""
      Just (op, id) -> to_haskell op ++ to_haskell id

instance ToHaskell TTValueExpr where
  to_haskell = \case
    LE2 le -> " " ++ to_haskell le
    VE1 ve -> "\n    " ++ to_haskell ve

-- Program
instance ToHaskell Program where
  to_haskell = \(P (pp, pps)) -> to_haskell pp ++ show_list_sep "\n\n" pps

instance ToHaskell ProgramPart where
  to_haskell = \case
    VD2 vd -> to_haskell vd
    GVDs2 gvds -> to_haskell gvds
    TD td -> to_haskell td
    TNN1 tnn -> to_haskell tnn
    TPD tpd -> to_haskell tpd
    TT1 tt -> to_haskell tt

-- For fast vim navigation
-- Parsers.hs
-- Testing.hs
-- ASTTypes.hs
