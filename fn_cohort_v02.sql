 -- fn_vXX
 -- Cohort Cashflows
 -- versions
 --   v01 fn_cohort_v01 - uses new fn_orig,term,month tables
 --   v84 clean up
 --   v83 new syntax for parameters
 --     BY_<x> group by x
 --     D_<x> Display x
 --     F_<x> Filter by x
 --     O_<x> Order by x
 --     ROLL rollup
 --   v01 fn_perf uses the new tables fn_orig/term/month 20240514
 --   v81 added having count(*) to truncate low loan counts
 --   v77 fixed fncrt_sfloan_v02 adds cpp formatting
 --   v76 nano, uses fncrt_sfloan_v02 simplified table 20240212
 --   v75 orig bal  B=[1,2,4] => B0=1 B1=2 B2=4
 --   v74 orig bal  BAL0 - BALN
 --   v73 SUMONLY and check BY_AGE and D_HIST which are incompatible
 --   v72 fixes NULL in output
 --   v70 assigns average coupon based on bycuts
 --   v69 ltv filters, bymi to examine effect of mi
 --   v68 use balance segment from temp
 --   v67 reorient grouping for BY_AGE
 --   v65 can determine LOWBAL as < 50 pctile, MED < 80 pctile,
 --   	  flags BY_BALP or D_BALP
 --   v64 can specify loan balance cutoffs, flags BY_BAL or D_BAL LBALK and MBALK
 --
 --   uses temporary tables to capture determine universe of loan_ids and
 --   	   summarize group-by parameters
 --   calculates CPRs for BY_AGE and D_HIST (24 months)
 --   adds originator ranking
 --   adds servicer ranking
 --
 -- NOTES:
 --
 -- TAGS: designed to pass through sed filter
 --   /*_XXX_  _XXX_*/ and #XXX# comment tags will be removed
 --     _XXX_ standalone will optionally be replaced by value 
 --     because mysql does not nest /* */ filters, use #XXX# to "nest" filters
 --   tag naming convention:
 --     BYXXXX surround group-by sections to faciliate grouping,
 --	  e.g., BY_CHAN group by channel
 --             BY_AGE joins factor data to group by LOAN_AGE, increases query time
 --     +XXXX  surround display fields, e.g. D_GEO shows states %
 --            some tags such as D_HIST add additional joins to obtain the data,
 --	         increases query time
 --     XXX0 - XXXN define a range 0 being first and N the last, e.g., VIN0 - VINN
 --   special examples:
 --	AVCP: query calculates then filters for average coupon
 --	BY_AGE: query joins history to get timeseries by loan_age, DO NOT
 -- 	       COMBINE with D_HIST
 --	BY_BAL if this flag is used, then must define LBALK=275 and MBALK=425
 --	      (example values for 2022)
 --	  if high_balance_loan_indicator = 'N' AND
 -- 	    0 < orig_upb <= LBALK*1000            -> 'LOW' balance loan 
 --	    LBALK*1000 < orig_upb <= MBALK*1000   -> 'MED' balance loan
 -- 	    MBALK*1000 < orig_upb                 -> 'HIGH' balance loan
 --	  if high_balance_loan_indicator = 'Y'    -> 'SUPER' conforming bal loan
 -- 
 -- 	  https://sf.freddiemac.com/working-with-us/selling-delivery/delivery-options-pricing/cash-payups
 --       e.g. Low loan balances (LLBs): $85K, $110K, $125K, $150K, $175K,
 --	       $200K, $225K, $250K and $275K
 --     KEEPLOG: for debugging, copies temporary tables to review _LAST_SUMMARY
 --		 and _LAST_FILTERED_LOAN_IDS
 --     LIM: restricts the query to LIM loans
 --	TOPST: only top states
 --	SUMONLY: exit after summary pass
 --

#include "format_v02.cpp"



#if defined(BY_AGE) && defined(D_HIST)
select "BY_AGE and D_HIST are incompatible switches, exiting.." as Message;
exit
#endif

set @pp_horz := 24; # for D_HIST prepays in 1st @pp_horz months
set @dq_horz := 48; # for D_HIST dqs in 1st @dq_horz months
 -- most recent act_period = 202212 -- 202206
 -- latest first_pay with 24 months age is 202101 -- 202007
##set @pp_max_first_pay := '202101'; # dynamic (see below)
#F_VINT_START# set @start_year:=F_VINT_START;
#F_VINT_END# set @end_year:=F_VINT_END;
#F_VIN0# set @start_year:=F_VIN0;
#F_VINN# set @end_year:=F_VINN;
#F_VINT# set @start_year:=F_VINT;
#F_VINT# set @end_year:=F_VINT;
set @row_num:=0;
set @main_row_num:=0;
set @upb_vlowpctile:=0.10; # upper range of VLB, lower range of LLB
set @upb_lowpctile:=0.40; # upper range of LLB, lower range of MLB
set @upb_medpctile:=0.80; # upper range of MLB

select max(act_period) into @pp_max_first_pay from fn_month ;


 -- ------------------------------------
 -- ------------------------------------
 -- Creates the filtered list of loan_ids
 -- ------------------------------------
 -- ------------------------------------

drop  table if exists _temp_filtered_loan_ids;

create temporary table  _temp_filtered_loan_ids(
       loan_id decimal(12,0) unsigned not null unique
       ,orig_rate decimal(5,3) unsigned
       ,orig_rate_pctile decimal(16,12) unsigned
       /*_BY_CHAN_       ,channel enum('R','C','B') _BY_CHAN_*/
       /*_BY_SELL_       ,seller_rank decimal(3,0) _BY_SELL_*/
       /*_BY_SVCR_       ,servicer_rank decimal(3,0) _BY_SVCR_*/
       ,orig_upb decimal(16,2) unsigned
       ,orig_upb_pctile decimal(16,12) unsigned
       ,loan_term decimal(3,0) unsigned
       ,orig_date char(6)
       /*_BY_FRST_       ,first_flag enum('Y','N') _BY_FRST_*/
       /*_BY_2HOM_       ,second_home enum('Y','N') _BY_2HOM_*/
       /*_BY_MI_       	,mi_flag enum('Y','N') _BY_MI_*/
       /*_BY_ST_       	,state char(2) _BY_ST_*/
       /*_BY_HBAL_       ,high_balance_loan_indicator enum('Y','N') _BY_HBAL_*/
       ,eligible enum('Y','N')
       /*_BY_VINT_       ,vintage char(4) _BY_VINT_*/
       			,bal_seg varchar(20) ### enum('VLOW','LOW','MED','HIGH','SUPER')  
);


insert into _temp_filtered_loan_ids
(
	loan_id
	, orig_rate
	, orig_rate_pctile
       /*_BY_CHAN_       ,channel  _BY_CHAN_*/
       /*_BY_SELL_       ,seller_rank  _BY_SELL_*/
       /*_BY_SVCR_       ,servicer_rank  _BY_SVCR_*/
       ,orig_upb
       ,orig_upb_pctile
       ,loan_term 
       ,orig_date 
       /*_BY_FRST_       ,first_flag  _BY_FRST_*/
       /*_BY_2HOM_       ,second_home _BY_2HOM_*/
       /*_BY_MI_  	,mi_flag _BY_MI_*/
       /*_BY_ST_       	,state  _BY_ST_*/
       /*_BY_HBAL_       ,high_balance_loan_indicator  _BY_HBAL_*/
       ,eligible
       /*_BY_VINT_       ,vintage _BY_VINT_*/
       /*_BY_BAL_	,bal_seg _BY_BAL_*/
       /*_BY_BALP_	,bal_seg _BY_BALP_*/
       /*_BY_BSTP_	,bal_seg _BY_BSTP_*/
)
select
	loan_id
	, orig_rate
	, orig_rate_pctile
       /*_BY_CHAN_       ,channel  _BY_CHAN_*/
       /*_BY_SELL_       ,seller_rank  _BY_SELL_*/
       /*_BY_SVCR_       ,servicer_rank  _BY_SVCR_*/
       ,orig_upb
       ,orig_upb_pctile
       ,loan_term 
       ,orig_date 
       /*_BY_FRST_       ,first_flag  _BY_FRST_*/
       /*_BY_2HOM_       ,second_home _BY_2HOM_*/
       /*_BY_MI_       	,mi_flag _BY_MI_*/
       /*_BY_ST_       	,state  _BY_ST_*/
       /*_BY_HBAL_       ,high_balance_loan_indicator  _BY_HBAL_*/
       ,eligible
       /*_BY_VINT_       ,vintage _BY_VINT_*/
       /*_BY_BAL_	,bal_seg _BY_BAL_*/
       /*_BY_BALP_	,bal_seg _BY_BALP_*/
       /*_BY_BSTP_	,bal_seg _BY_BSTP_*/
      from
	(
		select substring(orig.orig_date,1,4) as vintage
		,orig.seller as originator
		,orig.loan_id
		,orig.orig_date
		,orig.orig_term
		,orig.state
		,orig.orig_rate
		,orig.orig_upb
		,orig.channel
		,orig.high_balance_loan_indicator
		,orig.first_flag
		,case when orig.occ_stat='S' then 'Y' else 'N' end as second_home
		,orig.mi_pct
		,orig.mi_type
		,case when mi_type = 1 then 'Y' else 'N' end as mi_flag -- mi_type=1 is borrower paid
		,orig.first_pay
		,orig.seller
		,orig.servicer
		,orig.dti
		,orig.oltv
		,orig.ocltv
		,orig.cscore_b
		,orig.cscore_c
		,orig.no_units
		,orig.num_bo
		,orig.prop
		,orig.occ_stat
		,orig.purpose
		,orig.property_inspection_waiver_indicator
		,orig.loan_term
		, least(ifnull(orig.cscore_c,999), orig.cscore_b) as QFICO
		,case when orig.OCC_STAT != 'I'
		        and ifnull(orig.DTI,100) <=45
			and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))<=95
			and least(ifnull(orig.cscore_c,999), orig.cscore_b) >= 640
			and orig.prop != 'MH'		     
			and orig.state not in ('PR','VI')
        and ifnull(orig.PROPERTY_INSPECTION_WAIVER_INDICATOR,'A') = 'A'
	## 5(b)(iii)
	and if(ifnull(orig.OLTV,100)>65,
	    if(least(ifnull(orig.cscore_c,999), orig.cscore_b) >= 660,TRUE,FALSE),
	    TRUE)
	## 5(b)(v)
	and if(
		(orig.purpose='C' and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))>=80 and orig.orig_term >= 240)
	          or (orig.prop='CO' and ifnull(orig.OLTV,100)>=80)
		  or (orig.NO_UNITS>=2 and ifnull(orig.OLTV,100)>=75)
		  or (orig.OCLTV is not null and orig.OCLTV<90 and orig.OLTV>=70)
	    ,
	    if(orig.cscore_b >= 700 and ifnull(orig.DTI,100)<=45,TRUE,FALSE),
	    TRUE)
	## 5(b)(vi)
	and if(orig.OCLTV is not null and orig.OCLTV>=90 and orig.OLTV>=70,
	    if(orig.cscore_b >= 720 and ifnull(orig.DTI,100) <=43, TRUE,FALSE),
	    TRUE)
  then 'Y' else 'N' end as eligible
  -- 5(b)(iii)
,  case when (ifnull(orig.OLTV,100)>65 and
	    (least(ifnull(orig.cscore_c,999), orig.cscore_b) < 660)) then 'Y' else 'N' end
	    				      		     as INEL_B3_FICO_LT_660
  -- ineligible under 5(b)(v)
, case when (
    (orig.purpose='C' and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))>=80 and orig.orig_term >= 240)
      or (orig.prop='CO' and ifnull(orig.OLTV,100)>=80)
        or (orig.NO_UNITS>=2 and ifnull(orig.OLTV,100)>=75)
	  or (orig.OCLTV is not null and orig.OCLTV<90 and orig.OLTV>=70)
	    ) and (orig.cscore_b < 700 or ifnull(orig.DTI,100) >45) then 'Y' else 'N' end
	      	  		       	   			    as INEL_B5_CASH_CONDO_2FAM_CLTV_LT90
  -- ineligible under 5(b)(vi)								    
, case when  orig.OCLTV is not null and orig.OCLTV>=90 and orig.OLTV>=70
    and (orig.cscore_b < 720 or ifnull(orig.DTI,100) >43) then 'Y' else 'N' end as INEL_B6_CLTV_GT90
    --
, case when least(ifnull(orig.cscore_c,999), orig.cscore_b) < 760
    and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))>=85 then 'Y' else 'N' end as SUBLIMIT_A_GT_85
, case when least(ifnull(orig.cscore_c,999), orig.cscore_b) < 720
    and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))>=75
      and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))<85 then 'Y' else 'N' end as SUBLIMIT_B_75_85
      --
#ifdef BY_BAL
, case
  when orig.high_balance_loan_indicator = 'Y' then 'SUPER'
  #MBALK# when orig_upb  > _MBALK_*1000 then 'HIGH' 
  #LBALK# when orig_upb  > _LBALK_*1000 then 'MED'  
  #CVLBALK# when orig_upb  > _VLBALK_*1000 then 'LOW'  
  else 'VLOW' end as bal_seg
#endif  BY_BAL
# B0=085 B1=110 B2=125 B3=150 B4=175 B5=200 B6=225 B7=250 B8=275 B9=500
#ifdef BY_BSTP
, case
  when orig.high_balance_loan_indicator = 'Y' then 'SUPER'
  #B0# when orig_upb <= _B0_*1000 then '_B0_K'   
  #B1# when orig_upb <= _B1_*1000 then '_B1_K'   
  #B2# when orig_upb <= _B2_*1000 then '_B2_K'   
  #B3# when orig_upb <= _B3_*1000 then '_B3_K'   
  #B4# when orig_upb <= _B4_*1000 then '_B4_K'   
  #B5# when orig_upb <= _B5_*1000 then '_B5_K'   
  #B6# when orig_upb <= _B6_*1000 then '_B6_K'   
  #B7# when orig_upb <= _B7_*1000 then '_B7_K'   
  #B8# when orig_upb <= _B8_*1000 then '_B8_K'   
  #B9# when orig_upb <= _B9_*1000 then '_B9_K'   
  else 'CONF' end as bal_seg
#endif BSTP
#ifdef D_BAL
, case
  when orig.high_balance_loan_indicator = 'Y' then 'SUPER'
  #MBALK# when orig_upb  > _MBALK_*1000 then 'HIGH' 
  #LBALK# when orig_upb  > _LBALK_*1000 then 'MED'  
  #CVLBALK# when orig_upb  > _VLBALK_*1000 then 'LOW'  
  else 'VLOW' end as bal_seg
#endif D_BAL
#ifdef BY_BALP
, case
  when orig.high_balance_loan_indicator = 'Y' then 'SUPER'
  when percent_rank() over (partition by high_balance_loan_indicator,vintage order by orig_upb) < @upb_vlowpctile
       then 'VLOW'
  when percent_rank() over (partition by high_balance_loan_indicator,vintage order by orig_upb) < @upb_lowpctile
       then 'LOW'
  when percent_rank() over (partition by high_balance_loan_indicator,vintage order by orig_upb) < @upb_medpctile
       then 'MED'
  else 'HIGH' end as bal_seg
#endif BY_BALP
#ifdef D_BALP
, case
  when orig.high_balance_loan_indicator = 'Y' then 'SUPER'
  when percent_rank() over (partition by high_balance_loan_indicator,vintage order by orig_upb) < @upb_vlowpctile
       then 'VLOW'
  when percent_rank() over (partition by high_balance_loan_indicator,vintage order by orig_upb) < @upb_lowpctile
       then 'LOW'
  when percent_rank() over (partition by high_balance_loan_indicator,vintage order by orig_upb) < @upb_medpctile
       then 'MED'
  else 'HIGH' end as bal_seg
#endif D_BALP

 , case when coalesce(high_balance_loan_indicator,'N') = 'N' then
  percent_rank() over (partition by high_balance_loan_indicator,vintage order by orig_upb) end as orig_upb_pctile
 , percent_rank() over (partition by vintage order by orig_rate) as orig_rate_pctile
from
( select
fn_orig.loan_id
,fn_orig.orig_date
,fn_orig.orig_term
,fn_orig.orig_rate
,fn_orig.orig_upb
,fn_orig.channel
,fn_orig.high_balance_loan_indicator
,fn_orig.first_flag
,fn_orig.first_pay
,fn_orig.seller
,fn_orig.servicer
,fn_orig.dti
,fn_orig.oltv
,fn_orig.ocltv
,fn_orig.cscore_b
,fn_orig.cscore_c
,fn_orig.no_units
,fn_orig.prop
,fn_orig.occ_stat
,fn_orig.purpose
,fn_orig.state
,fn_orig.mi_pct
,fn_orig.mi_type
,fn_orig.num_bo
,fn_orig.property_inspection_waiver_indicator
, case when fn_orig.orig_term > 360 then 480
  when fn_orig.orig_term > 240 then 360
  when fn_orig.orig_term > 180 then 240
  else 180 end as loan_term
,substr( fn_orig.orig_date,1,4) as vintage

from
fn_orig
left join fn_term
on
	fn_orig.loan_id = fn_term.loan_id
where 1=1
	and (zb_dte is null or zb_dte > first_pay)
       and substring(orig_date,1,4)>=@start_year
       and substring(orig_date,1,4)<=@end_year
       /*_ORIGMO_ and orig_date in ( _ORIGMO_ ) _ORIGMO_*/
      /*_F_TERM_ 
       and  _F_TERM_ = case when fn_orig.orig_term > 360 then 480
       when fn_orig.orig_term > 240 then 360
         when fn_orig.orig_term > 180 then 240
	   else 180 end
	_F_TERM_*/
	/*_BAL0_ and fn_orig.orig_upb > _BAL0_*1000 _BAL0_*/
	/*_BALN_ and fn_orig.orig_upb <= _BALN_*1000 _BALN_*/
      /*_F_ST_ and state='_F_ST_'  _F_ST_*/
      /*_F_EXST_ and state <> '_F_EXST_'  _F_EXST_*/
      /*_F_RATE_ and orig_rate = _F_RATE_ _F_RATE_*/
      /*_F_CHAN_ and channel = '_F_CHAN_' _F_CHAN_*/
      /*_TOPST25_ -- top 25 states in 2022 making up 88% of loan vol and 85% count
       and state in ('CA','TX','FL','AZ','CO','WA','GA','NC','VA','NY',
       	   	     'UT','NJ','PA','IL','TN','OR','MD','MI','OH','MN',
		     'NV','SC','MA','IN','MO')  
       _TOPST25_*/
      /*_TOPST12_ -- top 12 states in 2022 making up 64% of loan vol and 57% count
       and state in ('CA','TX','FL','AZ','CO','WA','GA','NC','VA','NY',
       	   	     'UT','NJ')
       _TOPST12_*/
      /*_LIM_ limit _LIM_  _LIM_*/
) orig
where 1=1
       and substring(orig.orig_date,1,4)>=@start_year
       and substring(orig.orig_date,1,4)<=@end_year
       /*_ORIGMO_ and orig_date in ( _ORIGMO_ ) _ORIGMO_*/
       /*_SELL_ and orig_seller.seller like 'Flagstar%' _SELL_*/
       /*_PRCH_ and orig.purpose='P'  _PRCH_*/
       /*_UNIT_ and orig.no_units=_UNIT_  _UNIT_*/
       /*_LTVMIN_ and coalesce(OCLTV,99) >= _LTVMIN_ and OLTV >= _LTVMIN_ _LTVMIN_*/
       /*_LTVMAX_ and coalesce(OCLTV,0) <= _LTVMAX_ and OLTV <= _LTVMAX_ _LTVMAX_*/
       /*_BY_MI_ and coalesce(mi_type,1) = 1  _BY_MI_*/
       /*_PURP_ and purpose=_PURP_  _PURP_*/
       /*_FILTER_*/
) loans
where 1=1
      /*_SELLN_ 
      and seller_rank >= _SELL0_ 
      and seller_rank <= _SELLN_  _SELLN_*/
      /*_F_ELIG_ and eligible = 'Y'       _F_ELIG_*/
      /*_ONLY30_ and loan_term = 360 _ONLY30_*/
      /*_F_TERM_ and loan_term=_F_TERM_ _F_TERM_*/
      /*_TOPST_
       and state in ('CA','TX','FL','MI', 'WA','CO','AZ','NY',
       	   	    'VA','NJ','IL','NC','MA','GA','PA','MD','UT')  _TOPST_*/
;

-- -----------------------------
-- -----------------------------
-- SUMMARIZE
-- -----------------------------
-- -----------------------------

drop  table if exists _temp_summary;
create temporary table  _temp_summary(
       loan_term decimal(3,0) unsigned
       ,wa_note_rate decimal(5,3) unsigned
       ,med_note_rate decimal(5,3) unsigned
       /*_BY_VINT_       ,vintage char(4) _BY_VINT_*/
       /*_BY_ST_       	,state char(2) _BY_ST_*/
       /*_BY_HBAL_       ,high_balance_loan_indicator enum('Y','N','0') _BY_HBAL_*/
       /*_BY_FRST_       ,first_flag enum('Y','N','0') _BY_FRST_*/
       /*_BY_2HOM_       ,second_home enum('Y','N','0') _BY_2HOM_*/
       /*_BY_MI_ 	,mi_flag enum('Y','N','0') _BY_MI_*/
       /*_BY_SELL_       ,seller_rank decimal(3,0) _BY_SELL_*/
       /*_BY_SVCR_       ,servicer_rank decimal(3,0) _BY_SVCR_*/
       /*_BY_CHAN_       ,channel enum('R','C','B','0') _BY_CHAN_*/
       			,bal_seg varchar(20) ##  enum('VLOW','LOW','MED','HIGH','SUPER','0')  
       			,max_bal decimal(16,2) unsigned
       ,loan_cnt decimal(8,0) unsigned
       ,orig_upb decimal(16,2) unsigned
);

create temporary table  _temp_summary2 like _temp_summary;

insert into _temp_summary
(
	loan_term
	, wa_note_rate
	, med_note_rate
	/*_BY_VINT_ , vintage _BY_VINT_*/
	/*_BY_ST_ , state _BY_ST_*/
	/*_BY_HBAL_ , high_balance_loan_indicator  _BY_HBAL_*/
	/*_BY_FRST_ , first_flag _BY_FRST_*/
	/*_BY_2HOM_ , second_home _BY_2HOM_*/
	/*_BY_MI_   , mi_flag _BY_MI_*/
	/*_BY_SELL_ , seller_rank _BY_SELL_*/
	/*_BY_SVCR_ , servicer_rank  _BY_SVCR_*/
	/*_BY_CHAN_ , channel _BY_CHAN_*/
       /*_BY_BAL_   , bal_seg,max_bal _BY_BAL_*/
       /*_BY_BALP_  , bal_seg,max_bal _BY_BALP_*/
       /*_BY_BSTP_  , bal_seg,max_bal _BY_BSTP_*/
	, loan_cnt
	, orig_upb
)
select
	coalesce(loan_term,0) as loan_term
	, round(sum(orig_rate*orig_upb)/sum(orig_upb)*8,0)/8 as wa_note_rate
	, round(avg(orig_rate),3) as med_note_rate
	/*_BY_VINT_ , coalesce(vintage,0) as vintage _BY_VINT_*/
	/*_BY_ST_ ,coalesce(state,'0') as state _BY_ST_*/
	/*_BY_HBAL_ , coalesce(high_balance_loan_indicator,'0') as high_balance_loan_indicator  _BY_HBAL_*/
	/*_BY_FRST_ , coalesce(first_flag,'0') as first_flag _BY_FRST_*/
	/*_BY_2HOM_ ,coalesce(second_home,'0') as second_home _BY_2HOM_*/
	/*_BY_MI_ ,coalesce(mi_flag,'0') as mi_flag _BY_MI_*/
	/*_BY_SELL_ , coalesce(seller_rank,0)  as seller_rank _BY_SELL_*/
	/*_BY_SVCR_ , coalesce(servicer_rank,0) as servicer_rank  _BY_SVCR_*/
	/*_BY_CHAN_ , coalesce(channel,'0') as channel _BY_CHAN_*/
       /*_BY_BAL_   , coalesce(bal_seg,'0') as bal_seg ,max(orig_upb) as max_bal _BY_BAL_*/
       /*_BY_BALP_   , coalesce(bal_seg,'0') as bal_seg ,max(orig_upb) as max_bal _BY_BALP_*/
       /*_BY_BSTP_   , coalesce(bal_seg,'0') as bal_seg ,max(orig_upb) as max_bal _BY_BSTP_*/
	,count(*) as loan_cnt
	,sum(orig_upb) as orig_upb
from _temp_filtered_loan_ids
group by loan_term
      /*_BY_BAL_ , bal_seg _BY_BAL_*/
      /*_BY_BALP_ , bal_seg _BY_BALP_*/
      /*_BY_BSTP_ , bal_seg _BY_BSTP_*/
      /*_BY_CHAN_ , channel _BY_CHAN_*/
      /*_BY_VINT_ , vintage _BY_VINT_*/
      /*_BY_ST_ ,state _BY_ST_*/
      /*_BY_HBAL_ , high_balance_loan_indicator  _BY_HBAL_*/
      /*_BY_FRST_ , first_flag _BY_FRST_*/
      /*_BY_2HOM_ , second_home _BY_2HOM_*/
      /*_BY_MI_ 	 , mi_flag _BY_MI_*/
      /*_BY_SELL_ , seller_rank  _BY_SELL_*/
      /*_BY_SVCR_ , servicer_rank  _BY_SVCR_*/
with rollup
order by loan_term desc
      /*_BY_VINT_ , vintage _BY_VINT_*/
      /*_BY_ST_ , state _BY_ST_*/
      /*_BY_HBAL_ , grouping(high_balance_loan_indicator), high_balance_loan_indicator _BY_HBAL_*/
      /*_BY_FRST_ ,  grouping(first_flag),first_flag _BY_FRST_*/
      /*_BY_2HOM_ ,  grouping(second_home),second_home _BY_2HOM_*/
      /*_BY_SELL_ ,grouping(seller_rank),-cast(seller_rank as unsigned) desc   _BY_SELL_*/
      /*_BY_SVCR_ ,grouping(servicer_rank),-cast(servicer_rank as unsigned) desc   _BY_SVCR_*/
      /*_BY_MI_ 	 ,  grouping(mi_flag),mi_flag _BY_MI_*/
      /*_BY_CHAN_ ,  grouping(channel), channel _BY_CHAN_*/
      /*_BY_BAL_ , grouping(bal_seg), bal_seg _BY_BAL_*/
      /*_BY_BALP_ , grouping(bal_seg), bal_seg _BY_BALP_*/
      /*_BY_BSTP_ , grouping(bal_seg), bal_seg _BY_BSTP_*/
;

-- ---------------------------
-- OPTIONALLY SELECT BY AVG COUPON OF SUMMARY
-- ---------------------------

#ifdef AVCP
-- clean up filtered loan table
delete from
_temp_filtered_loan_ids temp
where orig_rate <> ( select wa_note_rate
      from _temp_summary summ
      where 1=1
      and summ.loan_term = temp.loan_term
      /*_BY_VINT_       and summ.vintage = temp.vintage  _BY_VINT_*/
      /*_BY_ST_         and summ.state = temp.state _BY_ST_*/
      /*_BY_HBAL_       and summ.high_balance_loan_indicator = temp.high_balance_loan_indicator _BY_HBAL_*/
      /*_BY_FRST_       and summ.first_flag = '0' _BY_FRST_*/
      /*_BY_2HOM_       and summ.second_home = '0'  _BY_2HOM_*/
      /*_BY_MI_  	      and summ.mi_flag = '0'  _BY_MI_*/
      /*_BY_SELL_       and summ.seller_rank = 0 _BY_SELL_*/
      /*_BY_SVCR_       and summ.servicer_rank = 0 _BY_SVCR_*/
      /*_BY_CHAN_       and summ.channel = temp.channel _BY_CHAN_*/
      /*_BY_BAL_        and summ.bal_seg = temp.bal_seg _BY_BAL_*/
      /*_BY_BALP_        and summ.bal_seg = temp.bal_seg _BY_BALP_*/
      /*_BY_BSTP_        and summ.bal_seg = temp.bal_seg _BY_BSTP_*/
);

-- remake the summary table

delete from _temp_summary;

insert into _temp_summary
(
	loan_term
	, wa_note_rate
	, med_note_rate
		/*_BY_VINT_ , vintage _BY_VINT_*/
		/*_BY_ST_ , state _BY_ST_*/
		/*_BY_HBAL_ , high_balance_loan_indicator  _BY_HBAL_*/
		/*_BY_FRST_ , first_flag _BY_FRST_*/
		/*_BY_2HOM_ , second_home _BY_2HOM_*/
		/*_BY_MI_   , mi_flag _BY_MI_*/
		/*_BY_SELL_ , seller_rank _BY_SELL_*/
		/*_BY_SVCR_ , servicer_rank  _BY_SVCR_*/
		/*_BY_CHAN_ , channel _BY_CHAN_*/
	 /*_BY_BAL_   ,bal_seg, max_bal _BY_BAL_*/
	 /*_BY_BALP_  ,bal_seg , max_bal _BY_BALP_*/
	 /*_BY_BSTP_  ,bal_seg , max_bal _BY_BSTP_*/
	, loan_cnt
	, orig_upb
)
select
	coalesce(loan_term,0)
	, round(sum(orig_rate*orig_upb)/sum(orig_upb)*8,0)/8 as wa_note_rate
	, round(avg(orig_rate),3) as med_note_rate
	/*_BY_VINT_ , coalesce(vintage,0) _BY_VINT_*/
	/*_BY_ST_   , coalesce(state,'0') _BY_ST_*/
	/*_BY_HBAL_ , coalesce(high_balance_loan_indicator,'0')  _BY_HBAL_*/
	/*_BY_FRST_ , coalesce(first_flag,'0') _BY_FRST_*/
	/*_BY_2HOM_ , coalesce(second_home,'0') _BY_2HOM_*/
	/*_BY_MI_   , coalesce(mi_flag,'0') _BY_MI_*/
	/*_BY_SELL_ , coalesce(seller_rank,0)  _BY_SELL_*/
	/*_BY_SVCR_ , coalesce(servicer_rank,0)  _BY_SVCR_*/
	/*_BY_CHAN_ , coalesce(channel,'0') _BY_CHAN_*/
	/*_BY_BAL_  , coalesce(bal_seg,'0'),max(orig_upb) _BY_BAL_*/
	/*_BY_BALP_ , coalesce(bal_seg,'0'),max(orig_upb) _BY_BALP_*/
	/*_BY_BSTP_ , coalesce(bal_seg,'0'),max(orig_upb) _BY_BSTP_*/
	,count(*) as loan_cnt
	,sum(orig_upb) as orig_upb
from _temp_filtered_loan_ids
group by loan_term
      /*_BY_BAL_ , bal_seg _BY_BAL_*/
      /*_BY_BALP_ , bal_seg _BY_BALP_*/
      /*_BY_BSTP_ , bal_seg _BY_BSTP_*/
      /*_BY_CHAN_ , channel _BY_CHAN_*/
      /*_BY_VINT_ , vintage _BY_VINT_*/
      /*_BY_ST_ ,state _BY_ST_*/
      /*_BY_HBAL_ , high_balance_loan_indicator  _BY_HBAL_*/
      /*_BY_FRST_ , first_flag _BY_FRST_*/
      /*_BY_2HOM_ , second_home _BY_2HOM_*/
      /*_BY_MI_ 	, mi_flag _BY_MI_*/
      /*_BY_SELL_ , seller_rank  _BY_SELL_*/
      /*_BY_SVCR_ , servicer_rank  _BY_SVCR_*/
with rollup 
order by loan_term desc
      /*_BY_VINT_ , vintage _BY_VINT_*/
      /*_BY_ST_ , state _BY_ST_*/
      /*_BY_HBAL_ , grouping(high_balance_loan_indicator), high_balance_loan_indicator _BY_HBAL_*/
      /*_BY_FRST_ ,  grouping(first_flag),first_flag _BY_FRST_*/
      /*_BY_2HOM_ ,  grouping(second_home),second_home _BY_2HOM_*/
      /*_BY_SELL_ ,grouping(seller_rank),-cast(seller_rank as unsigned) desc   _BY_SELL_*/
      /*_BY_SVCR_ ,grouping(servicer_rank),-cast(servicer_rank as unsigned) desc   _BY_SVCR_*/
      /*_BY_MI_ 	,  grouping(mi_flag), mi_flag _BY_MI_*/
      /*_BY_CHAN_ ,  grouping(channel), channel _BY_CHAN_*/
      /*_BY_BAL_ ,  grouping(bal_seg), bal_seg _BY_BAL_*/
      /*_BY_BALP_ ,  grouping(bal_seg), bal_seg _BY_BALP_*/
      /*_BY_BSTP_ ,  grouping(bal_seg), bal_seg _BY_BSTP_*/
;
#endif AVCP

insert into _temp_summary2 select * from _temp_summary;

/*_KEEPLOG_ # if KEEPLOG tag then keep copies of the temporary tables, replace _TEMP_ prefix with _LAST_
drop table if exists _last_summary;
create table  _last_summary like _temp_summary;
insert into _last_summary select * from _temp_summary;

drop  table if exists _last_filtered_loan_ids;
create table   _last_filtered_loan_ids like _temp_filtered_loan_ids ;
insert into _last_filtered_loan_ids select * from  _temp_filtered_loan_ids ;

_KEEPLOG_*/


/*_SUMONLY_
select "Summary Only" as Message;
exit
_SUMONLY_*/



 -- ============================================================================
 -- ============================================================================
 -- TOPLEVEL QUERY Extract the data  ===========================================
 -- ============================================================================
 -- ============================================================================


#ifndef _ROLL_
#define grouping(x) x
#endif

select
#ifdef SAMPLECHECK
case when vintages = 0 then 'All' else substring(vintages,1,4) end   as "Vintage" 
,case when loan_term = 0 then 'All Terms' else loan_term end  as "Term"
,FC(CT_COHORT,0)					as "Loan Count"
,FC(OBAL_COHORT, 0)					as "UPB"
,FC(note_rates,3) 					as "Rate"
,FC(ALS,0) 						as ALS
, FC(oltv,1)				as OLTV
, FC(ocltv,1) 				as OCLTV
, FC(qfico,1) 				as "QFICO"
, FC(dti,1) 				as DTI
, FP(ca_pct,2)		as "CA %"
, FP(tx_pct,2) 		as "TX %"
, FP(ny_pct,2)		as "NY %"
, FP((1-channel_r_pct),1) 	as "TPO %"
, FP(coalesce(second_pct,0),1)	as "2nd Home %"
, FP(coalesce(first_pct,0),1) 	as "1st Buyer %"
, FP(coalesce(mi_flag_pct,0),1)	as "MI %"
, FP(coalesce(condo_pct,0),1) 	as "Condo %"
, FP(coalesce(mult_borr_pct,0),1) 	as "Mult Borw. %"
, FP(coalesce(twofam_pct,0),1) 	as "Mult. Units %"
, FP(appr_not_full_pct,1) 	as "Appr. Waiv. %"
, FP((1-coalesce(mapinel_pct,0)),1)		as "MAP Elig.%"
#else not samplecheck
 -- begin grouping sections
  /*_SELL_ originator, _SELL_*/
  /*_BY_SELL_
  ,seller_rank
  ,originator
  ,
  _BY_SELL_*/
  /*_BY_SVCR_
  servicer_rank
  ,servicer_name
  ,
  _BY_SVCR_*/
  case when loan_term = 0 then 'All Terms' else loan_term end  as "Cohort Term"
  /*_BY_VINT_ ,case when vintage = 0 then 'All' else vintage end   as "Cohort Vintage"  _BY_VINT_*/
  /*_BY_ST_   ,case when state = '0' then 'US' else state end 	  as "Cohort State"  _BY_ST_*/
  /*_BY_CHAN_ ,case when channel = '0' then 'All Orig. Channels' else channel end as "Cohort Channel"  _BY_CHAN_*/
  /*_BY_BAL_  ,case when bal_seg = '0' then 'Tot. Cohort' else bal_seg end as "Cohort Balance" _BY_BAL_*/
  /*_BY_BALP_ ,case when bal_seg = '0' then 'Tot. Cohort' else bal_seg end as "Cohort Balance"  _BY_BALP_*/
  /*_BY_BSTP_ ,case when bal_seg = '0' then 'Tot. Cohort' else bal_seg end as "Cohort Balance"  _BY_BSTP_*/
  /*_BY_FRST_ ,first_flag 	      	   	      		     as "Cohort 1st Home Buyer" _BY_FRST_*/
  /*_BY_2HOM_ ,case when second_home = 'N' then 'Primary Occ.' 
  	     	   when second_home='Y' then 'Second Home' 
		   else  'All Occ.' end  as "Cohort 2nd Home" _BY_2HOM_*/ 
  /*_BY_MI_   ,mi_flag 						     as "Cohort Has MI" _BY_MI_*/
  /*_BY_HBAL_ ,hbal 						     as "Cohort Super Conf Bal" _BY_HBAL_*/
 -- end grouping sections

 -- begin filters
  /*_VIN0_ , vintages as "Cohort Vintages" _VIN0_*/
  /*_F_ELIG_ ,eligible as "Cohort MAP Eligible"       _F_ELIG_*/
  /*_PRCH_ ,'P' as "Cohort Loan Purpose"  _PRCH_*/
  /*_UNIT_  ,_UNIT_ as "Cohort Units"  _UNIT_*/
  /*_LTVMIN_ ,_LTVMIN_ as "Cohort Min LTV"  _LTVMIN_*/
  /*_LTVMAX_ ,_LTVMAX_  as "Cohort Max LTV" _LTVMAX_*/
  /*_BY_MI_ ,'Y' as "Cohort Has MI"  _BY_MI_*/
  /*_PURP_ ,_PURP_ as "Cohort Purpose"  _PURP_*/

 -- end filters

 -- begin cohort loans info
,FC(CT_COHORT,0)					as "Cohort Orig #"
,FC(OBAL_COHORT, 0) 				as "Cohort Orig $"
,FC(OBAL_COHORT/CT_COHORT,0)			as "Cohort ALS"
 -- end cohort loans info


#ifdef BY_AGE
	  , loan_age					as "Loan Age"
	  , FP(cpr,2)  		as "CPR%"
	  , FP(D30DDPCT,2) 		as "30DD%"	  
	  , FP(D60DDPCT,2)  	as "60DD%"	  
	  , FP(D90PLUSPCT,2)  	as "90+DD%"	  
	  , FP(FCPCT,2)  		as "FC%"	  
	  , FP(
	    sum(case when loan_age is not null then defaulted_upb end) 
	    over (partition by loan_term

	  	  /*_BY_VINT_ ,vintage _BY_VINT_*/
	  	  /*_BY_FRST_ ,first_flag _BY_FRST_*/
	  	  /*_BY_2HOM_ ,second_home _BY_2HOM_*/
	  	  /*_BY_MI_   ,mi_flag _BY_MI_*/
	  	  /*_BY_HBAL_ ,hbal _BY_HBAL_*/
	  	  /*_BY_CHAN_ ,channel _BY_CHAN_*/
	  	  /*_BY_ST_   ,state _BY_ST_*/
	  	  /*_BY_BAL_  ,bal_seg _BY_BAL_*/
	  	  /*_BY_BALP_  ,bal_seg _BY_BALP_*/
	  	  /*_BY_BSTP_  ,bal_seg _BY_BSTP_*/

	    order by isnull(loan_age),loan_age)
	     /
	     OBAL_COHORT
 	,6)					as "Cum Def%"

	    ,FP(
	    sum(case when loan_age is not null then MO_NET_LOSS end) 
	    over (partition by loan_term
	  	  /*_BY_VINT_ ,vintage _BY_VINT_*/
	  	  /*_BY_FRST_ ,first_flag _BY_FRST_*/
	  	  /*_BY_2HOM_ ,second_home _BY_2HOM_*/
	  	  /*_BY_MI_ ,mi_flag _BY_MI_*/
	  	  /*_BY_HBAL_ ,hbal _BY_HBAL_*/
	  	  /*_BY_CHAN_ ,channel _BY_CHAN_*/
	  	  /*_BY_ST_   ,state _BY_ST_*/
	  	  /*_BY_BAL_  ,bal_seg _BY_BAL_*/
	  	  /*_BY_BALP_  ,bal_seg _BY_BALP_*/
	  	  /*_BY_BSTP_  ,bal_seg _BY_BSTP_*/

	    order by isnull(loan_age),loan_age)
	     /
	     OBAL_COHORT
 	,6)					as "Cum Loss%"

	  , coalesce(
	    FP(
	    sum(case when loan_age is not null then MO_NET_LOSS end) over (partition by loan_term
	  	  /*_BY_VINT_ ,vintage _BY_VINT_*/
		  /*_BY_FRST_ ,first_flag _BY_FRST_*/
		  /*_BY_2HOM_ ,second_home _BY_2HOM_*/
		  /*_BY_MI_ ,mi_flag _BY_MI_*/
	  	  /*_BY_HBAL_ ,hbal _BY_HBAL_*/
	  	  /*_BY_CHAN_ ,channel _BY_CHAN_*/
	  	  /*_BY_ST_   ,state _BY_ST_*/
	  	  /*_BY_BAL_  ,bal_seg  _BY_BAL_*/
	  	  /*_BY_BALP_  ,bal_seg  _BY_BALP_*/
	  	  /*_BY_BSTP_  ,bal_seg  _BY_BSTP_*/
	    order by isnull(loan_age),loan_age) 
	    /
	    sum(case when loan_age is not null then defaulted_upb end) 
	    	     over (partition by loan_term
	  	  /*_BY_VINT_ ,vintage _BY_VINT_*/
		  /*_BY_FRST_ ,first_flag _BY_FRST_*/
		  /*_BY_2HOM_ ,  second_home _BY_2HOM_*/
		  /*_BY_MI_ ,  mi_flag _BY_MI_*/
	  	  /*_BY_HBAL_ , hbal _BY_HBAL_*/
	  	  /*_BY_CHAN_ ,  channel _BY_CHAN_*/
	  	  /*_BY_ST_ ,state _BY_ST_*/
	  	  /*_BY_BAL_ ,bal_seg _BY_BAL_*/
	  	  /*_BY_BALP_ ,bal_seg _BY_BALP_*/
	  	  /*_BY_BSTP_ ,bal_seg _BY_BSTP_*/

	    order by isnull(loan_age),loan_age) 
	    ,1) ,'')				as "Cum LGD%"
	  -- following age data from top-level query are primarily for 
	  -- consistency checking & debugging

	  , FC(loan_ct,0)				as "Loans"
	  , FC(current_upb,0) 			as "Curr Bal$"
	  , FC(orig_upb,0) 				as "Orig Bal$"
	  , FP(smm,6) 		as "SMM%"
	  , FC(sched_bal,0) 			as "Sched Bal$"
	  , FC(unsched_prin,0) 			as "Unsched Prin$"
	  , FC(unsched_cnt,0) 			as "Unsched Cnt"
	  , FC(defaulted_upb,0) 			as "Mo Defaults$"
	  , FC(defaulted_cnt,0) 			as "Mo Def Cnt"
	  , FC(coalesce(MO_NET_LOSS,0),0) 		as "Mo Net Loss$"	  
	  , FC(coalesce(loss_cnt,0),0) 		as "Mo Loss Cnt"	  
	  , FC(sum(case when loan_age is not null then defaulted_upb end) over (partition by loan_term

	  	  /*_BY_VINT_ ,vintage _BY_VINT_*/
		  /*_BY_FRST_ ,first_flag _BY_FRST_*/
		  /*_BY_2HOM_ ,second_home _BY_2HOM_*/
		  /*_BY_MI_ ,mi_flag _BY_MI_*/
	  	  /*_BY_HBAL_ ,hbal _BY_HBAL_*/
	  	  /*_BY_CHAN_ ,channel _BY_CHAN_*/
	  	  /*_BY_ST_   ,state _BY_ST_*/
	  	  /*_BY_BAL_ ,bal_seg _BY_BAL_*/
	  	  /*_BY_BALP_ ,bal_seg _BY_BALP_*/
	  	  /*_BY_BSTP_ ,bal_seg _BY_BSTP_*/

	    order by isnull(loan_age),loan_age),0)	as "Cum Def$"
	  , FC(sum(case when loan_age is not null then MO_NET_LOSS end) over (partition by loan_term

	  	  /*_BY_VINT_ ,vintage _BY_VINT_*/
		  /*_BY_FRST_ ,first_flag _BY_FRST_*/
		  /*_BY_2HOM_ ,second_home _BY_2HOM_*/
		  /*_BY_MI_ ,mi_flag _BY_MI_*/
	  	  /*_BY_HBAL_ ,hbal _BY_HBAL_*/
	  	  /*_BY_CHAN_ ,channel _BY_CHAN_*/
	  	  /*_BY_ST_   ,state _BY_ST_*/
	  	  /*_BY_BAL_ ,bal_seg _BY_BAL_*/
	  	  /*_BY_BALP_ ,bal_seg _BY_BALP_*/
	  	  /*_BY_BSTP_ ,bal_seg _BY_BSTP_*/

	    order by isnull(loan_age),loan_age),0)	as "Cum Loss$"
#endif BY_AGE


/*_D_VINT_  , vintages as Vintages _D_VINT_*/

/*_D_STRT_
, format(orig_upb,0) 					as "Orig $"
, format(loan_ct,0)					as "Loan #"
, format(ALS,0) 					as ALS
, concat(format(minlsize/1000,0),'k-',
   format(maxlsize/1000,0),'k') 			as "LS Range"
_D_STRT_*/
, format(note_rate,3)					as "WA Rate"

 
/*_D_CHAN_
, concat(format(channel_b_pct*100,2),'%')	as "Broker %"
, concat(format(channel_c_pct*100,2),'%') 	as "Channel %"
, concat(format(channel_r_pct*100,2),'%') 	as "Retail %"
_D_CHAN_*/
/*_D_BAL_
, concat(format(bal_vlow_pct*100,2),'%')	as "V.Low Bal %"
, concat(format(bal_low_pct*100,2),'%')		as "Low Bal %"
, concat(format(bal_med_pct*100,2),'%')		as "Med Bal %"
, concat(format(bal_high_pct*100,2),'%')	as "High Bal %"
, concat(format(bal_super_pct*100,2),'%')	as "Super Bal %"
_D_BAL_*/
/*_D_BALP_
, concat(format(bal_vlow_pct*100,2),'%')	as "V.Low Bal %"
, concat(format(bal_low_pct*100,2),'%')		as "Low Bal %"
, concat(format(bal_med_pct*100,2),'%')		as "Med Bal %"
, concat(format(bal_high_pct*100,2),'%')	as "High Bal %"
, concat(format(bal_super_pct*100,2),'%')	as "Super Bal %"
_D_BALP_*/
/*_D_GEO_
  -- selection of high speed states
, concat(format(ca_pct*100,2),'%')		as "CA%"
, concat(format(az_pct*100,2),'%') 		as "AZ%"
, concat(format(ut_pct*100,2),'%') 		as "UT%"
, concat(format(co_pct*100,2),'%') 		as "CO%"
, concat(format(nv_pct*100,2),'%') 		as "NV%"
  -- selection of HPI/CREDIT states
, concat(format(id_pct*100,2),'%')		as "ID%"
, concat(format(fl_pct*100,2),'%') 		as "FL%"
, concat(format(wy_pct*100,2),'%') 		as "WY%"
, concat(format(tx_pct*100,2),'%') 		as "TX%"
, concat(format(mi_pct*100,2),'%') 		as "MI%"
  -- district
, concat(format(ny_pct*100,2),'%')		as "NY%"
, concat(format(nj_pct*100,2),'%') 		as "NJ%"
_D_GEO_*/
/*_D_STRT_
, concat(format(coalesce(hbal_pct,0)*100,2),'%')	as "HBal%"
  -- credit characteristics
, concat(format(coalesce(second_pct,0)*100,2),'%')	as "2nd Home %"
, concat(format(coalesce(mi_flag_pct,0)*100,2),'%')	as "MI %"
, concat(format(coalesce(cashout_pct,0)*100,2),'%') 	as "Cashout %"
, concat(format(coalesce(first_pct,0)*100,2),'%') 	as "1st Buyer %"
, concat(format(coalesce(condo_pct,0)*100,2),'%') 	as "Condo %"
, concat(format(coalesce(twofam_pct,0)*100,2),'%') 	as "2+Fam %"
  -- credit metrics
, format(oltv,1)				as OLTV
, format(ocltv,1) 				as OCLTV
, format(cscore_b,1) 				as "Bor. FICO"
, format(cscore_c,1) 				as "Cob. FICO"
, format(qfico,1) 				as "Qual. FICO"
, format(dti,1) 				as DTI

  -- eligibility results
, concat(format(coalesce(mapinel_pct,0)*100,2),'%')		as "MAP Inel.%"
_D_STRT_*/
/*_D_ELIG_
, concat(format(invest_pct*100,2),'%')		as "Inv. %"
, concat(format(cscore_c_lt_640_pct*100,2),'%') as "FICO<640%"
, concat(format(ltv_gt_95_pct*100,2),'%') 	as "LTV>95%"
, concat(format(dti_gt_45_pct*100,2),'%') 	as "DTI>45%"
, concat(format(mh_pct*100,2),'%') 		as "MH%"
, concat(format(pr_vi_pct*100,2),'%') 		as "PR|VI%"
# , concat(format(io_pct*100,2),'%') 		as "IO%"
, concat(format(appr_not_full_pct*100,2),'%') 	as "Appr. not Full %"
, concat(format(appr_waiver_pct*100,2),'%') 	as "Appr. Waiv %"
, concat(format(inel_b3_fico_lt_660_pct*100,2),'%')	as "Inel FICO<660"
, concat(format(INEL_B5_CASH_CONDO_2FAM_CLTV_LT90_PCT*100,2),'%')	as "Inel Cash,Condo,2fam,CLTV<90%"
, concat(format(INEL_B6_CLTV_GT90_PCT*100,2),'%') 	as "Inel CLTV>90%"
_D_ELIG_*/
/*_D_STRT_
, concat(format(coalesce(SUBLIMIT_A_GT_85_PCT,0)*100,2),'%')	as "SUB A%"
, concat(format(coalesce(SUBLIMIT_B_75_85_PCT,0)*100,2),'%') 	as "SUB B%"
  -- prepay performance 
_D_STRT_*/
 /*_D_HIST_
, concat(format(coalesce(horz_cpr,0)*100,2),'%')	as "CPR Horz."
  -- credit performance
, dq_horz					as "DQ Horz."
, concat(format(coalesce(horz_ever_60dd,0)
	     / OBAL_COHORT
 	*100,6),'%')				as "Ev.60DD Horz. %"
, concat(format(coalesce(ever_60dd,0)
	     / OBAL_COHORT
 	*100,6),'%')				as "Life 60DD %"
 _D_HIST_*/
/*_D_STRT_  
, concat(format(coalesce(default_upb,0)
	     / OBAL_COHORT
	      	*100,6),'%')			as "Def @ Cutoff%"

, concat(format(coalesce(net_loss_to_date,0)
	     / OBAL_COHORT
 	*100,6),'%')				as "Loss @ Cutoff%"
, concat(format(severity*100,3),'%') 		as "LGD @ Cutoff%"
_D_STRT_*/
 -- Details for consistency checking & debugging
, note_rates 						as "Rate WA"
, format(round(8*note_rate,0)/8,3) 			as "Rate WA 8ths"
, format(wa_mopandi,0) 					as "P&I WA"

/*_BY_BAL_ 
, concat('_LBALK_','k',' - ','_MBALK_',k')		as "Med L.S. Criteria"
, size_range				as "L.S. Range"
, size_pctiles				as "L.S. Pctiles"
_BY_BAL_*/
/*_BY_BALP_ 
, concat(format(@upb_lowpctile,2),' - ',format(@upb_medpctile,2))
  				    	as "Med L.S. Criteria"
, size_range				as "L.S. Range"
, size_pctiles				as "L.S. Pctiles"
_BY_BALP_*/

 /*_D_HIST_
, pp_horz				as "PP Horz. Mo"
, format(horz_act,0) 			as "Horz. Act $"
, format(horz_sched_upb,0) 		as "Horz. Sched $"
 _D_HIST_*/
/*_D_STRT_
, format(default_upb,0)			as "Def @ Cutoff $"
, format(default_cnt,0) 		as "Def @ Cutoff #"
, format(net_loss_to_date,0) 		as "Loss @ Cutoff $"
, format(loss_cnt_to_date,0) 		as "Loss @ Cutoff #"
  
_D_STRT_*/

#endif SAMPLECHECK
from
( -- ==========================================================
  -- TOP SUBQUERY (level exists only to bring in get cohort statistics)
  -- ==========================================================
	select grouped.*
,(select loan_cnt from _temp_summary tempsum where 1=1
	and tempsum.loan_term = coalesce(grouped.loan_term,0)
	/*_BY_VINT_ and tempsum.vintage = coalesce(grouped.vintage,0) _BY_VINT_*/
	/*_BY_ST_ and tempsum.state = coalesce(grouped.state,'0') _BY_ST_*/
	/*_BY_HBAL_ and_tempsum.high_balance_loan_indicator = coalesce(grouped.high_balance_loan_indicator,'0')  _BY_HBAL_*/
	/*_BY_FRST_ and tempsum.first_flag = coalesce(grouped.first_flag,'0') _BY_FRST_*/
	/*_BY_2HOM_ and tempsum.second_home = coalesce(grouped.second_home,'0') _BY_2HOM_*/
	/*_BY_MI_   and tempsum.mi_flag = coalesce(grouped.mi_flag,'0') _BY_MI_*/
	/*_BY_SELL_ and tempsum.seller_rank = coalesce(grouped.seller_rank,0)  _BY_SELL_*/
	/*_BY_SVCR_ and tempsum.servicer_rank = coalesce(grouped.servicer_rank,0)  _BY_SVCR_*/
	/*_BY_CHAN_ and tempsum.channel = coalesce(grouped.channel,'0') _BY_CHAN_*/
	/*_BY_BAL_ and tempsum.bal_seg = coalesce(grouped.bal_seg,'0') _BY_BAL_*/
	/*_BY_BALP_ and tempsum.bal_seg = coalesce(grouped.bal_seg,'0') _BY_BALP_*/
	/*_BY_BSTP_ and tempsum.bal_seg = coalesce(grouped.bal_seg,'0') _BY_BSTP_*/
	) as CT_COHORT
,(select orig_upb from _temp_summary2 tempsum where 1=1
	and tempsum.loan_term = coalesce(grouped.loan_term,0)
	/*_BY_VINT_ and tempsum.vintage = coalesce(grouped.vintage,0) _BY_VINT_*/
	/*_BY_ST_ and tempsum.state = coalesce(grouped.state,'0') _BY_ST_*/
	/*_BY_HBAL_ and_tempsum.high_balance_loan_indicator = coalesce(grouped.high_balance_loan_indicator,'0')  _BY_HBAL_*/
	/*_BY_FRST_ and tempsum.first_flag = coalesce(grouped.first_flag,'0') _BY_FRST_*/
	/*_BY_2HOM_ and tempsum.second_home = coalesce(grouped.second_home,'0') _BY_2HOM_*/
	/*_BY_MI_ and tempsum.mi_flag = coalesce(grouped.mi_flag,'0') _BY_MI_*/
	/*_BY_SELL_ and tempsum.seller_rank = coalesce(grouped.seller_rank,0)  _BY_SELL_*/
	/*_BY_SVCR_ and tempsum.servicer_rank = coalesce(grouped.servicer_rank,0)  _BY_SVCR_*/
	/*_BY_CHAN_ and tempsum.channel = coalesce(grouped.channel,'0') _BY_CHAN_*/
	/*_BY_BAL_ and tempsum.bal_seg = coalesce(grouped.bal_seg,'0') _BY_BAL_*/
	/*_BY_BALP_ and tempsum.bal_seg = coalesce(grouped.bal_seg,'0') _BY_BALP_*/
	/*_BY_BSTP_ and tempsum.bal_seg = coalesce(grouped.bal_seg,'0') _BY_BSTP_*/
	) as OBAL_COHORT
from
( -- ==========================================================
  -- GROUPED SUBQUERY 
  -- ==========================================================
select
0 as dummy, -- for grouping
@main_row_num:=@main_row_num+1 as main_row_num,
/*_SELL_ min(originator) as originator, _SELL_*/
/*_BY_SELL_
 -- case when grouping(seller_rank)=1 then 'Total' else seller_rank end as 
seller_rank
, min(originator) end as originator
,
_BY_SELL_*/
/*_BY_SVCR_
servicer_rank -- case when grouping(servicer_rank)=1 then 'Total' else servicer_rank end as servicer_rank
,servicer -- ,case when grouping(servicer_rank)=1 then 'Total' else min(servicer) end as servicer
,
_BY_SVCR_*/
loan_term -- coalesce(loan_term,0) as loan_term -- case when grouping(loan_term)=1 then 'Total' else loan_term  end  as loan_term
 /*_BY_VINT_ ,vintage _BY_VINT_*/
/*_BY_FRST_ , first_flag _BY_FRST_*/
/*_BY_2HOM_ , second_home _BY_2HOM_*/
/*_BY_MI_ , mi_flag _BY_MI_*/
/*_BY_HBAL_ , high_balance_loan_indicator as hbal _BY_HBAL_*/
/*_BY_CHAN_ ,  coalesce(channel,'0') as channel _BY_CHAN_*/
/*_BY_ST_ , coalesce(state,'0') as state  _BY_ST_*/
/*_BY_BAL_ ,  coalesce(bal_seg,'0') as bal_seg _BY_BAL_*/
/*_BY_BALP_ ,  coalesce(bal_seg,'0') as bal_seg _BY_BALP_*/
/*_BY_BSTP_ ,  coalesce(bal_seg,'0') as bal_seg _BY_BSTP_*/
, concat(min(vintage),'-',max(vintage)) as vintages
, sum(orig_rate*orig_upb)/sum(orig_upb) as note_rate
, concat(format(min(orig_rate),3),'-',format(max(orig_rate),3)) as note_rates
#ifdef NEVER
,(1-grouping(loan_term))
/*_BY_VINT_ * (1-grouping(vintage)) _BY_VINT_*/
/*_BY_ST_   * (1-grouping(state)) _BY_ST_*/
/*_BY_HBAL_ * (1-grouping(high_balance_loan_indicator))  _BY_HBAL_*/
/*_BY_FRST_ * (1-grouping(first_flag)) _BY_FRST_*/
/*_BY_2HOM_ * (1-grouping(second_home)) _BY_2HOM_*/
/*_BY_MI_ * (1-grouping(mi_flag)) _BY_MI_*/
/*_BY_SELL_ * (1-grouping(seller_rank))  _BY_SELL_*/
/*_BY_SVCR_ * (1-grouping(servicer_rank))  _BY_SVCR_*/
/*_BY_CHAN_ * (1-grouping(channel)) _BY_CHAN_*/
/*_BY_BAL_ * (1-grouping(bal_seg)) _BY_BAL_*/
/*_BY_BALP_ * (1-grouping(bal_seg)) _BY_BALP_*/
/*_BY_BSTP_ * (1-grouping(bal_seg)) _BY_BSTP_*/
as NOT_AGGREGATE
#endif NEVER
, count(*) as loan_ct
, sum(orig_upb) as orig_upb
, avg(orig_upb) as ALS
, min(orig_upb) as minlsize
, max(orig_upb) as maxlsize
, sum(mopandi*orig_upb)/sum(orig_upb) as wa_mopandi
, min(loans.eligible) as eligible
/*_BY_BAL_
, concat(format(min(orig_upb)/1000,0),'k',' - ',format(max(orig_upb)/1000,0),'k') as size_range
, concat(format(min(orig_upb_pctile)*100,0),'-',format(max(orig_upb_pctile)*100,0)) as size_pctiles
_BY_BAL_*/
/*_BY_BALP_
, concat(format(min(orig_upb)/1000,0),'k',' - ',format(max(orig_upb)/1000,0),'k') as size_range
, concat(format(min(orig_upb_pctile)*100,0),'-',format(max(orig_upb_pctile)*100,0)) as size_pctiles
_BY_BALP_*/
/*_BY_BSTP_
, concat(format(min(orig_upb)/1000,0),'k',' - ',format(max(orig_upb)/1000,0),'k') as size_range
, concat(format(min(orig_upb_pctile)*100,0),'-',format(max(orig_upb_pctile)*100,0)) as size_pctiles
_BY_BSTP_*/

/*_BY_AGE_ 
	  , loan_age
	  , sum(current_upb)				as current_upb  
	  , sum(sched_bal) 				as sched_bal
	  , sum(unsched_prin) 				as unsched_prin
	  , sum(unsched_cnt) 				as unsched_cnt
	  , case when sum(sched_bal)>0 
	      then sum(unsched_prin)/sum(sched_bal) end as smm
	  , case when sum(sched_bal)>0 
	      then (1-power(1-sum(unsched_prin)/sum(sched_bal),12)) end as cpr
	  , case when sum(current_upb)>0 
	     then sum(D30)/sum(current_upb) end		as D30DDPCT
	  , case when sum(current_upb)>0 
	      then sum(D60)/sum(current_upb) end	as D60DDPCT
	  , case when sum(current_upb)>0 
	    	 then sum(D90PLUS)/sum(current_upb) end as D90PLUSPCT
	  , case when sum(current_upb)>0 
	    	 then coalesce(sum(defaulted_upb),0)/sum(current_upb) end as FCPCT
	  , coalesce(sum(defaulted_upb),0) 		as defaulted_upb
	  , coalesce(count(defaulted_upb),0) 		as defaulted_cnt
	  , coalesce(sum(MO_NET_LOSS),0) 		as MO_NET_LOSS
	  , coalesce(count(case when MO_NET_LOSS > 0 
	    then 1 end),0)				as loss_cnt

_BY_AGE_*/

, sum(case when channel='B' then orig_upb end)/sum(orig_upb) as channel_b_pct
, sum(case when channel='C' then orig_upb end)/sum(orig_upb) as channel_c_pct
, sum(case when channel='R' then orig_upb end)/sum(orig_upb) as channel_r_pct

/*_D_BAL_
, sum(case when bal_seg='VLOW' then orig_upb end)/sum(orig_upb) as bal_vlow_pct
, sum(case when bal_seg='LOW' then orig_upb end)/sum(orig_upb) as bal_low_pct
, sum(case when bal_seg='MED' then orig_upb end)/sum(orig_upb) as bal_med_pct
, sum(case when bal_seg='HIGH' then orig_upb end)/sum(orig_upb) as bal_high_pct
, sum(case when bal_seg='SUPER' then orig_upb end)/sum(orig_upb) as bal_super_pct
_D_BAL_*/
/*_D_BALP_
, sum(case when bal_seg='VLOW' then orig_upb end)/sum(orig_upb) as bal_vlow_pct
, sum(case when bal_seg='LOW' then orig_upb end)/sum(orig_upb) as bal_low_pct
, sum(case when bal_seg='MED' then orig_upb end)/sum(orig_upb) as bal_med_pct
, sum(case when bal_seg='HIGH' then orig_upb end)/sum(orig_upb) as bal_high_pct
, sum(case when bal_seg='SUPER' then orig_upb end)/sum(orig_upb) as bal_super_pct
_D_BALP_*/

  -- selection of high speed states
, sum(case when state='CA' then orig_upb end)/sum(orig_upb) as ca_pct
, sum(case when state='AZ' then orig_upb end)/sum(orig_upb) as az_pct
, sum(case when state='UT' then orig_upb end)/sum(orig_upb) as ut_pct
, sum(case when state='CO' then orig_upb end)/sum(orig_upb) as co_pct
, sum(case when state='NV' then orig_upb end)/sum(orig_upb) as nv_pct
  -- selection of HPI/CREDIT states
, sum(case when state='ID' then orig_upb end)/sum(orig_upb) as id_pct
, sum(case when state='FL' then orig_upb end)/sum(orig_upb) as fl_pct
, sum(case when state='WY' then orig_upb end)/sum(orig_upb) as wy_pct
, sum(case when state='TX' then orig_upb end)/sum(orig_upb) as tx_pct
, sum(case when state='UT' then orig_upb end)/sum(orig_upb) as mi_pct
  -- district
, sum(case when state='NY' then orig_upb end)/sum(orig_upb) as ny_pct
, sum(case when state='NJ' then orig_upb end)/sum(orig_upb) as nj_pct

 -- _D_STRT_
, sum(case when high_balance_loan_indicator='Y' then orig_upb end)/sum(orig_upb) as hbal_pct
  -- credit characteristics
, sum(case when occ_stat='S' then orig_upb end)/sum(orig_upb) as second_pct
, sum(case when mi_type = 1 then orig_upb end)/sum(orig_upb) as mi_flag_pct
, sum(case when purpose='C' then orig_upb end)/sum(orig_upb) as cashout_pct
, sum(case when first_flag='Y' then orig_upb end)/sum(orig_upb) as first_pct
, sum(case when prop='CO' then orig_upb end)/sum(orig_upb) as condo_pct
, sum(case when NO_UNITS>=2 then orig_upb end)/sum(orig_upb) as twofam_pct
, sum(case when NUM_BO>=2 then orig_upb end)/sum(orig_upb) as mult_borr_pct
  -- credit metrics
, sum(orig_upb*oltv)/sum(case when oltv is not null then orig_upb end) as oltv
, sum(orig_upb*ocltv)/sum(case when ocltv is not null then orig_upb end) as ocltv
, sum(orig_upb*cscore_b)/sum(case when cscore_b is not null then orig_upb end) as cscore_b
, sum(orig_upb*cscore_c)/sum(case when cscore_c is not null then orig_upb end) as cscore_c
, sum(orig_upb*qfico)/sum(case when qfico is not null then orig_upb end) as qfico
, sum(orig_upb*dti)/sum(case when dti is not null then orig_upb end) as dti

  -- eligibility results
, sum(case when eligible='N' then orig_upb  end)/sum(orig_upb) as mapinel_pct
 -- _D_STRT_

, sum(case when OCC_STAT='I' then orig_upb end)/sum(orig_upb) as invest_pct
, sum(case when least(ifnull(cscore_c,999), cscore_b) < 640 then orig_upb end)/sum(orig_upb) as cscore_c_lt_640_pct
, sum(case when ifnull(OCLTV,ifnull(OLTV,100))>95 then orig_upb end)/sum(orig_upb) as ltv_gt_95_pct
, sum(case when DTI>45 then orig_upb end)/sum(orig_upb) as dti_gt_45_pct
, sum(case when PROP='MH' then orig_upb end)/sum(orig_upb) as mh_pct
, sum(case when STATE in ('PR,VI')  then orig_upb end)/sum(orig_upb) as pr_vi_pct
# , sum(case when ifnull(IO,'N') = 'Y' then orig_upb end)/sum(orig_upb) as io_pct
, sum(case when ifnull(PROPERTY_INSPECTION_WAIVER_INDICATOR,'A') <> 'A'then orig_upb end)/sum(orig_upb) as appr_not_full_pct
, sum(case when ifnull(PROPERTY_INSPECTION_WAIVER_INDICATOR,'A') = 'W'then orig_upb end)/sum(orig_upb) as appr_waiver_pct
, sum(case when INEL_B3_FICO_LT_660='Y' then orig_upb end)/
  			 sum(orig_upb)		as inel_b3_fico_lt_660_pct
, sum(case when INEL_B5_CASH_CONDO_2FAM_CLTV_LT90='Y' then orig_upb end)/
  			 sum(orig_upb) as INEL_B5_CASH_CONDO_2FAM_CLTV_LT90_PCT
, sum(case when INEL_B6_CLTV_GT90='Y' then orig_upb end)/sum(orig_upb) as INEL_B6_CLTV_GT90_PCT

/*_D_STRT_
, sum(case when SUBLIMIT_A_GT_85='Y' then orig_upb end)/sum(orig_upb) as SUBLIMIT_A_GT_85_PCT
, sum(case when SUBLIMIT_B_75_85='Y' then orig_upb end)/sum(orig_upb) as SUBLIMIT_B_75_85_PCT
  -- prepay performance 
_D_STRT_*/
 /*_D_HIST_
, max(@pp_horz) as pp_horz
, coalesce(sum(current_upb),0) as horz_act
, sum(horz_sched_upb) as horz_sched_upb
, (1-power(coalesce(sum(current_upb),0)/sum(horz_sched_upb),12/@pp_horz)) as horz_cpr
  -- credit performance
, max(@dq_horz) as dq_horz
, sum(horz_60dd) as horz_ever_60dd
, sum(ever_60dd) as ever_60dd
 _D_HIST_*/
/*_D_STRT_  
, coalesce(sum(case when ZERO_BAL_CODE in ('02','03','09','15')
  		  and DISPOSITION_DATE is not null then last_upb end),0) as default_upb
, coalesce(count(case when ZERO_BAL_CODE in ('02','03','09','15')
  		  and DISPOSITION_DATE is not null then last_upb end),0) as default_cnt
, sum(NET_LOSS) as net_loss_to_date
, coalesce(count(case when NET_LOSS > 0 then 1 end),0) as loss_cnt_to_date
, case when sum(case when ZERO_BAL_CODE in ('02','03','09','15')
  		  and DISPOSITION_DATE is not null then last_upb end) > 0 then
		  coalesce(sum(NET_LOSS),0)/sum(case when ZERO_BAL_CODE in ('02','03','09','15')
  		  			 and DISPOSITION_DATE is not null then last_upb end) 
		else 0 end as severity
_D_STRT_*/
from
( -- ==========================================================
  -- LOANS SUBQUERY 
  -- ==========================================================

select vintage  -- select substring(orig.orig_date,1,4) as vintage
,orig.seller as originator
,orig.loan_id
,orig.orig_date
,orig.orig_term
,orig.orig_rate
,orig.orig_upb
,orig.channel
,orig.high_balance_loan_indicator
,orig.first_flag
,orig.first_pay
,orig.seller
,orig.servicer
,orig.dti
,orig.oltv
,orig.ocltv
,orig.cscore_b
,orig.cscore_c
,orig.no_units
,orig.num_bo
,orig.prop
,orig.occ_stat
,orig.purpose
,orig.state
,orig.property_inspection_waiver_indicator
,orig.loan_term
,orig.mi_pct
,orig.mi_type
,round(orig.orig_upb*orig.orig_rate/1200*
	power(1+orig.orig_rate/1200,orig.orig_term)/
	(power(1+orig.orig_rate/1200,orig.orig_term)-1),2) as mopandi # assumes level payment
	
, case when orig.occ_stat='S' then 'Y' else 'N' end as second_home
, case when orig.mi_type = 1 then 'Y' else 'N' end as mi_flag -- mi_type=1 is borrower paid
, least(ifnull(orig.cscore_c,999), orig.cscore_b) as QFICO
 /*_D_HIST_
 , case when hist.current_upb = 0 and hist.LOAN_AGE is not NULL then
   orig.orig_upb*
	(power(1+orig.orig_rate/1200,orig.orig_term)
	- power(1+orig.orig_rate/1200,hist.loan_age ))
	/(power(1+orig.orig_rate/1200,orig.orig_term)-1)
	   -- formula reference https://www.wallstreetmojo.com/mortgage-formula/
   else hist.current_upb end as CURRENT_UPB
 _D_HIST_*/
/*_BY_SELL_  ,seller_rank  _BY_SELL_*/
/*_BY_SVCR_  ,servicer_rank  _BY_SVCR_*/

/*_BY_AGE_
 -- FN doesn't give us current_upb for 1st 6 months so we IMPROVISE
 , case when hist.current_upb = 0 and hist.LOAN_AGE is not NULL then
   orig.orig_upb*
	(power(1+orig.orig_rate/1200,orig.orig_term)
	- power(1+orig.orig_rate/1200,hist.loan_age ))
	/(power(1+orig.orig_rate/1200,orig.orig_term)-1)
	   -- formula reference https://www.wallstreetmojo.com/mortgage-formula/
   else hist.current_upb end							as CURRENT_UPB

, case when hist.LOAN_AGE is null then -- FN data sets age to NULL on foreclosure so we IMPROVISE date diff
  12*(substr(hist.ACT_PERIOD,1,4)-substr(orig.FIRST_PAY,1,4))+
  (substr(hist.ACT_PERIOD,5,2)-substr(orig.FIRST_PAY,5,2))+1
  else
  hist.LOAN_AGE end								as LOAN_AGE
  -- do delinquency buckets
, case when hist.DLQ_STATUS='01' and hist.LOAN_AGE is not null then
  case when hist.current_upb > 0 then
    hist.current_upb
  else -- FN doesn't give us current_upb for 1st 6 months so we IMPROVISE calculate amortized ubp
   orig.orig_upb*
	(power(1+orig.orig_rate/1200,orig.orig_term)
	- power(1+orig.orig_rate/1200,hist.loan_age ))
	/(power(1+orig.orig_rate/1200,orig.orig_term)-1) end else 0 end		as D30
, case when hist.DLQ_STATUS='02'  and hist.LOAN_AGE is not null  then
  case when hist.current_upb > 0 then
    hist.current_upb
  else
   orig.orig_upb*
	(power(1+orig.orig_rate/1200,orig.orig_term)
	- power(1+orig.orig_rate/1200,hist.loan_age ))
	/(power(1+orig.orig_rate/1200,orig.orig_term)-1) end else 0 end		as D60
, case when hist.DLQ_STATUS>='03' and hist.LOAN_AGE is not null then
  case when hist.current_upb > 0 then
    hist.current_upb
  else
   orig.orig_upb*
	(power(1+orig.orig_rate/1200,orig.orig_term)
	- power(1+orig.orig_rate/1200,hist.loan_age ))
	/(power(1+orig.orig_rate/1200,orig.orig_term)-1) end else 0 end		as D90PLUS

  , case when term.ZERO_BAL_CODE in ('02' -- Third party sale
    	      			    ,'03' -- Short sale
				    ,'09' -- Deed-in-Lieu, REO Disposition
				    ,'15' -- notes sales
				    )
  		  and term.DISPOSITION_DATE is not null then term.last_upb end	as defaulted_upb

  ,case when term.ZERO_BAL_CODE>1 then greatest(0,
	(term.LAST_UPB
	+term.FORECLOSURE_COSTS
	+term.PROPERTY_PRESERVATION_AND_REPAIR_COSTS
	+term.ASSET_RECOVERY_COSTS
	+term.MISCELLANEOUS_HOLDING_EXPENSES_AND_CREDITS
	+term.ASSOCIATED_TAXES_FOR_HOLDING_PROPERTY)
	-
  	(term.NET_SALES_PROCEEDS
	+term.CREDIT_ENHANCEMENT_PROCEEDS
	+term.REPURCHASES_MAKE_WHOLE_PROCEEDS
	+term.OTHER_FORECLOSURE_PROCEEDS)
	)
	else NULL  end							as MO_NET_LOSS


 -- PREPAYMENT SCHED_BAL UNSCHED_PRIN
 , case when hist.current_upb = 0 and hist.LOAN_AGE is not NULL then
   orig.orig_upb*
	(power(1+orig.orig_rate/1200,orig.orig_term)
	- power(1+orig.orig_rate/1200,hist.loan_age ))
	/(power(1+orig.orig_rate/1200,orig.orig_term)-1)
	   -- formula reference https://www.wallstreetmojo.com/mortgage-formula/
   when hist.current_upb = 0 and hist.LOAN_AGE is NULL then
   	term.LAST_UPB
   else hist.current_upb end						as SCHED_BAL
,  case when term.ZERO_BAL_CODE = 01 then term.LAST_UPB else 0 end 	as UNSCHED_PRIN
,  case when term.ZERO_BAL_CODE = 01 then 1 else 0 end 	as UNSCHED_CNT
_BY_AGE_*/

, bal_seg
, orig_upb_pctile

/*_D_STRT_
	,greatest(0,
	(term.LAST_UPB
	+term.FORECLOSURE_COSTS
	+term.PROPERTY_PRESERVATION_AND_REPAIR_COSTS
	+term.ASSET_RECOVERY_COSTS
	+term.MISCELLANEOUS_HOLDING_EXPENSES_AND_CREDITS
	+term.ASSOCIATED_TAXES_FOR_HOLDING_PROPERTY)
	-
  	(term.NET_SALES_PROCEEDS
	+term.CREDIT_ENHANCEMENT_PROCEEDS
	+term.REPURCHASES_MAKE_WHOLE_PROCEEDS
	+term.OTHER_FORECLOSURE_PROCEEDS)
	) as NET_LOSS

_D_STRT_*/

, case when orig.first_pay <= @pp_max_first_pay then -- only if seasoned beyond @pp_horz months
       orig.orig_upb*(power(1+orig.orig_rate/1200,orig.orig_term)-power(1+orig.orig_rate/1200,@pp_horz))/
	(power(1+orig.orig_rate/1200,orig.orig_term)-1) end		as horz_sched_upb
,case when orig.OCC_STAT != 'I'
        and ifnull(orig.DTI,100) <=45
	and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))<=95
        and least(ifnull(orig.cscore_c,999), orig.cscore_b) >= 640
        and orig.prop != 'MH'		     
        and orig.state not in ('PR','VI')
        and ifnull(orig.PROPERTY_INSPECTION_WAIVER_INDICATOR,'A') = 'A'
	## 5(b)(iii)
	and if(ifnull(orig.OLTV,100)>65,
	    if(least(ifnull(orig.cscore_c,999), orig.cscore_b) >= 660,TRUE,FALSE),
	    TRUE)
	## 5(b)(v)
	and if(
		(orig.purpose='C' and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))>=80 and orig.orig_term >= 240)
	          or (orig.prop='CO' and ifnull(orig.OLTV,100)>=80)
		  or (orig.NO_UNITS>=2 and ifnull(orig.OLTV,100)>=75)
		  or (orig.OCLTV is not null and orig.OCLTV<90 and orig.OLTV>=70)
	    ,
	    if(orig.cscore_b >= 700 and ifnull(orig.DTI,100)<=45,TRUE,FALSE),
	    TRUE)
	## 5(b)(vi)
	and if(orig.OCLTV is not null and orig.OCLTV>=90 and orig.OLTV>=70,
	    if(orig.cscore_b >= 720 and ifnull(orig.DTI,100) <=43, TRUE,FALSE),
	    TRUE)
  then 'Y' else 'N' end							as eligible # ELIGIBLE # # ELIGIBLE # # ELIGIBLE # # ELIGIBLE #
  -- 5(b)(iii)
,  case when (ifnull(orig.OLTV,100)>65 and
	    (least(ifnull(orig.cscore_c,999), orig.cscore_b) < 660)) then 'Y' else 'N' end
	    				      		       	     as INEL_B3_FICO_LT_660
  -- ineligible under 5(b)(v)
, case when (
    (orig.purpose='C' and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))>=80 and orig.orig_term >= 240)
      or (orig.prop='CO' and ifnull(orig.OLTV,100)>=80)
        or (orig.NO_UNITS>=2 and ifnull(orig.OLTV,100)>=75)
	  or (orig.OCLTV is not null and orig.OCLTV<90 and orig.OLTV>=70)
	    ) and (orig.cscore_b < 700 or ifnull(orig.DTI,100) >45) then 'Y' else 'N' end
	      	  		       	   			    as INEL_B5_CASH_CONDO_2FAM_CLTV_LT90
  -- ineligible under 5(b)(vi)								    
, case when  orig.OCLTV is not null and orig.OCLTV>=90 and orig.OLTV>=70
    and (orig.cscore_b < 720 or ifnull(orig.DTI,100) >43) then 'Y' else 'N' end as INEL_B6_CLTV_GT90
    --
, case when least(ifnull(orig.cscore_c,999), orig.cscore_b) < 760
    and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))>=85 then 'Y' else 'N' end as SUBLIMIT_A_GT_85
, case when least(ifnull(orig.cscore_c,999), orig.cscore_b) < 720
    and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))>=75
      and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))<85 then 'Y' else 'N' end as SUBLIMIT_B_75_85
      --
 /*_D_HIST_
, case when exists(select * from fn_month dlqhist
       where orig.loan_id = dlqhist.loan_id  and dlqhist.dlq_status >='02' and dlqhist.loan_age<= @dq_horz )
       then orig.orig_upb end 		     	 		    as horz_60dd
, case when exists(select * from fn_month dlqhist
       where orig.loan_id = dlqhist.loan_id  and dlqhist.dlq_status >='02' )
       then orig.orig_upb end 		     	 		    as ever_60dd
 _D_HIST_*/
,term.FORECLOSURE_DATE
,term.DISPOSITION_DATE
,term.LAST_UPB
##,term.LOAN_AGE as TERM_LOAN_AGE ## RNS20240515 tag
,term.ZERO_BAL_CODE
,term.ZB_DTE
,term.NET_SALES_PROCEEDS
,term.CREDIT_ENHANCEMENT_PROCEEDS
,term.REPURCHASES_MAKE_WHOLE_PROCEEDS
,term.OTHER_FORECLOSURE_PROCEEDS
,term.FORECLOSURE_COSTS
,term.PROPERTY_PRESERVATION_AND_REPAIR_COSTS
,term.ASSET_RECOVERY_COSTS
,term.MISCELLANEOUS_HOLDING_EXPENSES_AND_CREDITS
,term.ASSOCIATED_TAXES_FOR_HOLDING_PROPERTY
from
( -- ==========================================================
  -- ORIG SUBQUERY 
  -- ==========================================================
select
fn_orig.loan_id
,fn_orig.orig_date
,fn_orig.orig_term
,fn_orig.orig_rate
,fn_orig.orig_upb
,fn_orig.channel
,fn_orig.high_balance_loan_indicator
,fn_orig.first_flag
,fn_orig.first_pay
,fn_orig.seller
,fn_orig.servicer
,fn_orig.dti
,fn_orig.oltv
,fn_orig.ocltv
,fn_orig.cscore_b
,fn_orig.cscore_c
,fn_orig.no_units
,fn_orig.num_bo
,fn_orig.prop
,fn_orig.occ_stat
,fn_orig.purpose
,fn_orig.state
# ,fn_orig.ppmt_flg
# ,fn_orig.io
,fn_orig.mi_pct
,fn_orig.mi_type
,fn_orig.property_inspection_waiver_indicator
, case when fn_orig.orig_term > 360 then 480
  when fn_orig.orig_term > 240 then 360
  when fn_orig.orig_term > 180 then 240
  else 180 end as loan_term
, substring(fn_orig.orig_date,1,4) as vintage
, temp.bal_seg
, temp.orig_upb_pctile
from
fn_orig
, _temp_filtered_loan_ids temp
where fn_orig.loan_id = temp.loan_id
) orig
/*_BY_SELL_
inner join -- create a seller list
(
	select 
	case when coalesce(seller,'Other') = 'Other' 
	     then null 
	     else row_number() over (order by sum(orig_upb) desc)  end as seller_rank
	,coalesce(seller,'Other') as seller
			  --	(@row_num:=@row_num+1) as seller_rank
			  --	,seller
	,min(substr(orig_date,1,4)) as min_orig
	,max(substr(orig_date,1,4)) as max_orig
	from fn_orig orig
	where 1=1
		and substr(orig_date,1,4)>=@start_year
		and substr(orig_date,1,4)<=@end_year
	group by seller
	having coalesce(seller,'Other') <> 'Other' 
	order by sum(orig_upb) desc
) seller_list
on 1=1
   and coalesce(orig.seller,'Other') = seller_list.seller
   and substr(orig.orig_date,1,4)>=@start_year
   and substr(orig.orig_date,1,4)<=@end_year
_BY_SELL_*/
/*_BY_SVCR_
inner join -- create a servicer list
(
	select 
	case when coalesce(servicer,'Other') = 'Other' 
	     then null 
	     else row_number() over (order by sum(orig_upb) desc)  end as servicer_rank
	,coalesce(seller,'Other') as servicer
			  --	(@row_num:=@row_num+1) as servicer_rank
			  --	,servicer
	,min(substr(orig_date,1,4)) as min_orig
	,max(substr(orig_date,1,4)) as max_orig
	from fn_orig orig
	where 1=1
		and substr(orig_date,1,4)>=@start_year
		and substr(orig_date,1,4)<=@end_year
	group by servicer
	order by sum(orig_upb) desc
) servicer_list
on 1=1
   and coalesce(orig.seller,'Other') = servicer_list.seller
   and substr(orig.orig_date,1,4)>=@start_year
   and substr(orig.orig_date,1,4)<=@end_year
_BY_SVCR_*/
/*_BY_AGE_
LEFT JOIN
fn_month hist -- historical prepay
	     on 1=1
   	     and orig.loan_id=hist.loan_id
	     and ((hist.loan_age is null) or (hist.loan_age >= 0))
_BY_AGE_*/	     
 /*_D_HIST_
LEFT JOIN
fn_month hist -- historical prepay
	     on 1=1
   	     and orig.loan_id=hist.loan_id
	     and hist.loan_age = @pp_horz 
 _D_HIST_*/
LEFT JOIN
fn_term term -- terminal state
	      on orig.loan_id=term.loan_id
#if defined(BY_AGE) || defined(D_HIST)
	      and hist.act_period=term.act_period # RNS20240524
#endif	defined(BY_AGE) || defined(D_HIST)
where 1=1
       and substring(orig.orig_date,1,4)>=@start_year
       and substring(orig.orig_date,1,4)<=@end_year
       /*_SELL_ and orig_seller.seller like 'Flagstar%' _SELL_*/
       /*_PRCH_ and orig.purpose='P'  _PRCH_*/
       /*_FILTER_*/
) loans
group by loan_term
/*_BY_AGE_  , loan_age _BY_AGE_*/
/*_BY_BAL_  , bal_seg _BY_BAL_*/
/*_BY_BALP_ , bal_seg _BY_BALP_*/
/*_BY_BSTP_ , bal_seg _BY_BSTP_*/
/*_BY_CHAN_ , channel _BY_CHAN_*/
/*_BY_VINT_ , vintage _BY_VINT_*/
/*_BY_ST_   , state _BY_ST_*/
/*_BY_HBAL_ , high_balance_loan_indicator  _BY_HBAL_*/
/*_BY_FRST_ , first_flag _BY_FRST_*/
/*_BY_2HOM_ , second_home _BY_2HOM_*/
/*_BY_MI_   , mi_flag _BY_MI_*/
/*_BY_SELL_ , seller_rank  _BY_SELL_*/
/*_BY_SVCR_ , servicer_rank  _BY_SVCR_*/
/*_ROLL_ with rollup _ROLL_*/
/*_MINCOUNT_ having count(*) >= _MINCOUNT_ _MINCOUNT_*/
order by
loan_term desc
/*_BY_AGE_ ,dummy _BY_AGE_*/ -- dummy single group variable
/*_BY_VINT_ , vintage _BY_VINT_*/
/*_BY_ST_   , state _BY_ST_*/
/*_BY_HBAL_ , grouping(high_balance_loan_indicator), high_balance_loan_indicator _BY_HBAL_*/
/*_BY_FRST_ , grouping(first_flag),first_flag _BY_FRST_*/
/*_BY_2HOM_ , grouping(second_home),second_home _BY_2HOM_*/
/*_BY_SELL_ , grouping(seller_rank),-cast(seller_rank as unsigned) desc   _BY_SELL_*/
/*_BY_SVCR_ , grouping(servicer_rank),-cast(servicer_rank as unsigned) desc   _BY_SVCR_*/
/*_BY_MI_   , grouping(mi_flag), mi_flag _BY_MI_*/
/*_BY_CHAN_ , grouping(channel), channel _BY_CHAN_*/
/*_BY_BAL_  , grouping(bal_seg),
	  case bal_seg when 'VLOW' then 0 when 'LOW' then 1 when 'MED' then 2 when 'HIGH' then 3 when 'SUPER' then 4 end  _BY_BAL_*/
/*_BY_BALP_  , grouping(bal_seg),
	  case bal_seg when 'VLOW' then 0 when 'LOW' then 1 when 'MED' then 2 when 'HIGH' then 3 when 'SUPER' then 4 end  _BY_BALP_*/
/*_BY_BSTP_  , grouping(bal_seg),
	  case bal_seg when '085K' then 0 when '110K' then 1 when '125K' then 2 when '150K' then 3 when '175K' then 4 
	  when '200K' then 5 when '225K' then 6 when '250K' then 7 when '275K' then 8 when '500K' then 9 when 'CONF' then 10 
	  when 'SUPER' then 11 else 12 end  _BY_BSTP_*/
/*_BY_AGE_  , grouping(loan_age),loan_age _BY_AGE_*/
) grouped
where 1=1
/*_BY_AGE_ and loan_age is not null _BY_AGE_*/
## order by main_row_num
) top
;

##
##

