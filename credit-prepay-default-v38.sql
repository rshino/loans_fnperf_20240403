# credit vintage v38
# - v38 nano-ized
# - this version calculates CPRs
# adds originator ranking
# adds servicer ranking
# also one version does it all

# CPP macros for formatting

#define GET_MACRO(_0, _1, _2, NAME, ...) NAME
#define FP(...) GET_MACRO(_0, ##__VA_ARGS__, FP2, FP1, FP0)(__VA_ARGS__)
#define FC(...) GET_MACRO(_0, ##__VA_ARGS__, FC2, FC1, FC0)(__VA_ARGS__)

#ifdef HUMAN
#define FP2(x,prec) concat(format(x*100,prec),'%')
#define FP1(x) FP2(x,1)
#define FC2(x,prec) format(x,prec)
#define FC1(x) FC2(x,1)
#else
#define FP2(x,prec) round(x,prec+4)
#define FP1(x) FP2(x,1)
#define FC2(x,prec) round(x,prec+2)
#define FC1(x) FC2(x,1)
#endif



set @pp_term := 24;
set @dq_term := 48;
# most recent act_period = 202206
# latest first_pay with 24 months age is 202007
# set @pp_max_first_pay := '202007';
set @start_year:=_VINT_START_;
set @end_year:=_VINT_END_;
set @row_num:=0;


select max(act_period) into @pp_max_first_pay from fncrt_sfloan_v02 ;

select
/*_SELLER_ min(originator) as "Originator", _SELLER_*/
/*_BYSELLER_
case when grouping(seller_rank)=1 then 'Total' else seller_rank end as "Seller Rank"
,case when grouping(seller_rank)=1 then 'Total' else min(originator) end as "Originator"
,
_BYSELLER_*/
/*_BYSERVICER_
case when grouping(servicer_rank)=1 then 'Total' else servicer_rank end as "Servicer Rank"
,case when grouping(servicer_rank)=1 then 'Total' else min(servicer) end as "Servicer"
,
_BYSERVICER_*/
case when grouping(loan_term)=1 then 'Total' else loan_term  end  as "Term"
/*_VINT_ ,case when grouping(vintage)=1 then 'Total' else vintage end as "Vintage" _VINT_*/
/*_FIRST_ ,case when grouping(first_flag)=1 then 'Total' else first_flag end as "1st Home" _FIRST_*/
/*_CHAN_ , case when grouping(channel)=1 then 'All' else channel end as "Orig Chan" _CHAN_*/
/*_STATE_ ,case when grouping(state)=1 then 'Total' else state end as "State" _STATE_*/
, FC(count(*),0) as "Loans"
, FC(sum(orig_upb),0) as "Orig UPB"
/*_SHOWVINT_
, concat(min(vintage),'-',max(vintage)) as Vintages
_SHOWVINT_*/
/*_SHOWGEO_
  # SPEEDS
, FP(sum(case when state='CA' then orig_upb end)/sum(orig_upb),2) as "CA%"
, FP(sum(case when state='AZ' then orig_upb end)/sum(orig_upb),2) as "AZ%"
, FP(sum(case when state='UT' then orig_upb end)/sum(orig_upb),2) as "UT%"
, FP(sum(case when state='CO' then orig_upb end)/sum(orig_upb),2) as "CO%"
, FP(sum(case when state='NV' then orig_upb end)/sum(orig_upb),2) as "NV%"
  # HPI
, FP(sum(case when state='ID' then orig_upb end)/sum(orig_upb),2) aa "ID%"
, FP(sum(case when state='FL' then orig_upb end)/sum(orig_upb),2) as "FL%"
, FP(sum(case when state='WY' then orig_upb end)/sum(orig_upb),2) as "WY%"
, FP(sum(case when state='TX' then orig_upb end)/sum(orig_upb),2) as "TX%"
, FP(sum(case when state='UT' then orig_upb end)/sum(orig_upb),2) as "UT%"
, FP(sum(case when state='UT' then orig_upb end)/sum(orig_upb),2) as "MI%"
_SHOWGEO_*/

, FC(avg(orig_upb),0) as "ALS"
, FP(sum(case when high_balance_loan_indicator='Y' then orig_upb end)/sum(orig_upb),2) as "HBal%"
################### credit characteristics
, FP(sum(case when occ_stat='S' then orig_upb end)/sum(orig_upb)*100,2) as "2nd Home%"
, FP(sum(case when purpose='C' then orig_upb end)/sum(orig_upb)*100,2) as "Cashout%"
, FP(sum(case when first_flag='Y' then orig_upb end)/sum(orig_upb)*100,2) as "1st Home Buyer%"
, FP(sum(case when prop='CO' then orig_upb end)/sum(orig_upb)*100,2) as "Condo%"
, FP(sum(case when NO_UNITS>=2 then orig_upb end)/sum(orig_upb)*100,2) as "2+Fam%"
################### credit metrics
, FC(sum(orig_upb*oltv)/sum(case when oltv is not null then orig_upb end),1) as OLTV
, FC(sum(orig_upb*ocltv)/sum(case when ocltv is not null then orig_upb end),1) as OCLTV
, FC(sum(orig_upb*cscore_b)/sum(case when cscore_b is not null then orig_upb end),1) as "FICO"
, FC(sum(orig_upb*cscore_c)/sum(case when cscore_c is not null then orig_upb end),1) as "Cob. FICO"
, FC(sum(orig_upb*qfico)/sum(case when qfico is not null then orig_upb end),1) as "Qual. FICO"
, FC(sum(orig_upb*dti)/sum(case when dti is not null then orig_upb end),1) as DTI

####################### eligibility results
, concat(format(sum(case when ELIGIBLE='N' then orig_upb end)/sum(orig_upb)*100,2),'%') as "MAP Inel.%"
/*_SHOWELIG_
, FP(sum(case when OCC_STAT='I' then orig_upb end)/sum(orig_upb)*100,2) as "Invest%"
, FP(sum(case when least(ifnull(cscore_c,999), cscore_b) < 640 then orig_upb end)/sum(orig_upb)*100,2) as "FICO<640%"
, FP(sum(case when ifnull(OCLTV,ifnull(OLTV,100))>95 then orig_upb end)/sum(orig_upb)*100,2) as "LTV>95"
, FP(sum(case when DTI>45 then orig_upb end)/sum(orig_upb)*100,2) as "DTI>45"
, FP(sum(case when PROP='MH' then orig_upb end)/sum(orig_upb)*100,2) as "MH%"
, FP(sum(case when STATE in ('PR,VI')  then orig_upb end)/sum(orig_upb)*100,2) as "PR|VI%"
, FP(sum(case when ifnull(PROPERTY_INSPECTION_WAIVER_INDICATOR,'A') <> 'A'then orig_upb end)/sum(orig_upb)*100,2) as "Appr. not Full %"
, FP(sum(case when ifnull(PROPERTY_INSPECTION_WAIVER_INDICATOR,'A') = 'W'then orig_upb end)/sum(orig_upb)*100,2) as "Appr. Waiv %"
, FP(sum(case when INEL_B3_FICO_LT_660='Y' then orig_upb end)/
  			 sum(orig_upb)*100,2)		as "Inel FICO<660"
, FP(sum(case when INEL_B5_CASH_CONDO_2FAM_CLTV_LT90='Y' then orig_upb end)/
  			 sum(orig_upb)*100,2)		as "Inel Cash,Condo,2fam,CLTV<90%"
, FP(sum(case when INEL_B6_CLTV_GT90='Y' then orig_upb end)/sum(orig_upb)*100,2) as "Inel CLTV>90%"
_SHOWELIG*/
, FP(sum(case when SUBLIMIT_A_GT_85='Y' then orig_upb end)/sum(orig_upb)*100,2) as "SUB A%"
, FP(sum(case when SUBLIMIT_B_75_85='Y' then orig_upb end)/sum(orig_upb)*100,2) as "SUB B%"
###################### prepay performance 

, max(@pp_term) as "PP Horizon"
, FC(sum(current_upb),0) as "Horiz Act"
, FC(sum(sched_upb),0) as "Horiz Sched"
, FP(100*(1-power(sum(current_upb)/sum(sched_upb),12/@pp_term)),2) as "Horiz CPR"
###################### credit performance 
, FC(sum(case when ZERO_BAL_CODE in ('02','03','09','15')
  		  and DISPOSITION_DATE is not null then last_upb end),0) as "Defaulted UPB"
, FP(sum(case when ZERO_BAL_CODE in ('02','03','09','15')
  		  and DISPOSITION_DATE is not null then last_upb end)/sum(orig_upb)*100,2) as "Default %"
, max(@dq_term) as "DQ Horizon"
, FP(sum(ever_60P)/sum(orig_upb)*100,2) as "Ever 60"
, FP(sum(ever_120P)/sum(orig_upb)*100,2) as "Ever 120"

from
(
select substring(orig.orig_date,1,4) as vintage
,orig.seller as originator
  -- ,orig.servicer as servicer
/*_BYSELLER_  ,seller_rank  _BYSELLER_*/
/*_BYSERVICER_  ,servicer_rank  _BYSERVICER_*/
,least(0,
	term.NET_SALES_PROCEEDS+term.CREDIT_ENHANCEMENT_PROCEEDS
	+term.REPURCHASES_MAKE_WHOLE_PROCEEDS+term.OTHER_FORECLOSURE_PROCEEDS
	-term.LAST_UPB-term.FORECLOSURE_COSTS-term.PROPERTY_PRESERVATION_AND_REPAIR_COSTS-term.ASSET_RECOVERY_COSTS
	-term.MISCELLANEOUS_HOLDING_EXPENSES_AND_CREDITS-term.ASSOCIATED_TAXES_FOR_HOLDING_PROPERTY) as NET_LOSS
, hist.current_upb
, case when orig.first_pay <= @pp_max_first_pay then # only if seasoned beyond @pp_term months
         orig.orig_upb*(power(1+orig.orig_rate/1200,orig.orig_term)-power(1+orig.orig_rate/1200,@pp_term))/
	(power(1+orig.orig_rate/1200,orig.orig_term)-1) end as sched_upb
, case when orig.orig_term > 240 then 360
  when orig.orig_term > 180 then 240
  else 180 end as loan_term
,case when orig.OCC_STAT != 'I'
        and ifnull(orig.DTI,100) <=45
	and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))<=95
        and least(ifnull(orig.cscore_c,999), orig.cscore_b) >= 640
        and orig.prop != 'MH'		     
        and orig.state not in ('PR','VI')
        # and ifnull(orig.PPMT_FLG,'N') = 'N'
	# and ifnull(orig.IO,'N') = 'N'
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
  then 'Y' else 'N' end as ELIGIBLE
  ## 5(b)(iii)
,  case when (ifnull(orig.OLTV,100)>65 and
	    (least(ifnull(orig.cscore_c,999), orig.cscore_b) < 660)) then 'Y' else 'N' end
	    				      		     as INEL_B3_FICO_LT_660
  ## ineligible under 5(b)(v)
, case when (
    (orig.purpose='C' and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))>=80 and orig.orig_term >= 240)
      or (orig.prop='CO' and ifnull(orig.OLTV,100)>=80)
        or (orig.NO_UNITS>=2 and ifnull(orig.OLTV,100)>=75)
	  or (orig.OCLTV is not null and orig.OCLTV<90 and orig.OLTV>=70)
	    ) and (orig.cscore_b < 700 or ifnull(orig.DTI,100) >45) then 'Y' else 'N' end
	      	  		       	   			    as INEL_B5_CASH_CONDO_2FAM_CLTV_LT90
  ## ineligible under 5(b)(vi)								    
, case when  orig.OCLTV is not null and orig.OCLTV>=90 and orig.OLTV>=70
    and (orig.cscore_b < 720 or ifnull(orig.DTI,100) >43) then 'Y' else 'N' end as INEL_B6_CLTV_GT90
    ##
, case when least(ifnull(orig.cscore_c,999), orig.cscore_b) < 760
    and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))>=85 then 'Y' else 'N' end as SUBLIMIT_A_GT_85
, case when least(ifnull(orig.cscore_c,999), orig.cscore_b) < 720
    and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))>=75
      and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))<85 then 'Y' else 'N' end as SUBLIMIT_B_75_85
, least(ifnull(orig.cscore_c,999), orig.cscore_b) as QFICO
, case when exists(select * from fncrt_sfloan_v02 dlqhist
       where orig.loan_id = dlqhist.loan_id  and dlqhist.dlq_status >='02' and dlqhist.loan_age<= @dq_term )
       then orig.orig_upb end as ever_60P
, case when exists (select * from fncrt_sfloan_v02 dlqhist
       where orig.loan_id = dlqhist.loan_id and dlqhist.dlq_status >='04' and dlqhist.loan_age<= @dq_term )
       then orig.orig_upb end as ever_120P
, orig.*
, term.FORECLOSURE_DATE
, term.DISPOSITION_DATE
,term.LAST_UPB
,term.LOAN_AGE
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

fnsf_origination orig
/*_BYSELLER_
inner join
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
	from fnsf_origination orig
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
_BYSELLER_*/
/*_BYSERVICER_
inner join
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
	from fnsf_origination orig
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
_BYSERVICER_*/
left join
fnsf_terminal term -- terminal state
	      on orig.loan_id=term.loan_id
left join
fncrt_sfloan_v02 hist -- historical prepay
	     on 1=1
   	     and orig.loan_id=hist.loan_id
   	     and hist.loan_age = @pp_term
where 1=1
       and substring(orig.orig_date,1,4)>=@start_year
       and substring(orig.orig_date,1,4)<=@end_year
       /*_SELLER and orig_seller.seller like 'Flagstar%' SELLER_*/
       /*_FILTER_*/
) loans
where 1=1
      ## WHERE
      /*_SEGSELLER_ and seller_rank >= _MINSELLER_ and seller_rank <= _MAXSELLER_  _SEGSELLER_*/
      /*_ELIG_ and eligible = 'Y'       _ELIG_*/
      /*_ONLY30_ and loan_term = 360 _ONLY30_*/
      /*_TOPSTATES_
       and state in ('CA','TX','FL','MI', 'WA','CO','AZ','NY','VA','NJ','IL','NC','MA','GA','PA','MD','UT')  _TOPSTATES_*/
      /*_LIST_OF_STATES_*/
      ## GROUP
group by loan_term
/*_VINT_ , vintage _VINT_*/
/*_STATE_ ,state _STATE_*/
/*_CHAN_ , channel _CHAN_*/
/*_FIRST_ , first_flag _FIRST_*/
/*_BYSELLER_ , seller_rank  _BYSELLER_*/
/*_BYSERVICER_ , servicer_rank  _BYSERVICER_*/
with rollup 
order by loan_term desc
/*_VINT_ , vintage _VINT_*/
/*_STATE_ , state _STATE_*/
/*_BYSELLER_ ,grouping(seller_rank),-cast(seller_rank as unsigned) desc   _BYSELLER_*/
/*_BYSERVICER_ ,grouping(servicer_rank),-cast(servicer_rank as unsigned) desc   _BYSERVICER_*/
/*_CHAN_ ,  grouping(channel), channel _CHAN_*/
/*_FIRST_ ,  grouping(first_flag),first_flag _FIRST_*/

;
