 -- fnsfcf v46
 -- this version calculates CPRs
 -- adds originator ranking
 -- adds servicer ranking
 -- also one version does it all
set @pp_term := 24;
set @dq_term := 48;
 -- most recent act_period = 202212 -- 202206
 -- latest first_pay with 24 months age is 202101 -- 202007
set @pp_max_first_pay := '202101';
set @start_year:=_VIN0_;
set @end_year:=_VINN_;
set @row_num:=0;

select
/*_SELL_ min(originator) as "Originator", _SELL_*/
/*_BYSELL_
case when grouping(seller_rank)=1 then 'Total' else seller_rank end as "Seller Rank"
,case when grouping(seller_rank)=1 then 'Total' else min(originator) end as "Originator"
,
_BYSELL_*/
/*_BYSVCR_
case when grouping(servicer_rank)=1 then 'Total' else servicer_rank end as "Servicer Rank"
,case when grouping(servicer_rank)=1 then 'Total' else min(servicer) end as "Servicer"
,
_BYSVCR_*/
case when grouping(loan_term)=1 then 'Total' else loan_term  end  as "Term"
/*_BYVINT_ ,case when grouping(vintage)=1 then 'Total' else vintage end as "Vintage" _BYVINT_*/
/*_BYFRST_ ,case when grouping(first_flag)=1 then 'Total' else first_flag end as "1st Home" _BYFRST_*/
/*_BYHBAL_ ,case when grouping(high_balance_loan_indicator)=1 then 'Total' else high_balance_loan_indicator
	     end as "Hi-Bal." _BYHBAL_*/
/*_BYCHAN_ , case when grouping(channel)=1 then 'All' else channel end as "Orig Chan" _BYCHAN_*/
/*_BYST_ ,case when grouping(state)=1 then 'Total' else state end as "State" _BYST_*/


/*_+VINT_
, concat(min(vintage),'-',max(vintage)) as Vintages
_+VINT_*/
/*_+STRT_
, format(count(*),0) as "Loans"
, format(sum(orig_upb),0) as "Orig UPB"
, format(sum(orig_upb) over (),0) as "Tot Orig UPB"
, format(avg(orig_upb),0) as "ALS"
_+STRT_*/
/*_BYAGE_ 
	  , loan_age
	  , format(count(*),0) as "Loans"
	  , format(sum(current_upb),0) as current_upb  
	  , format(sum(orig_upb),0) as orig_upb  
	  , format(sum(sched_bal),0) as sched_bal
	  , format(sum(unsched_prin),0) as unsched_prin
	  , case when sum(sched_bal)>0 
	    then concat(format(sum(unsched_prin)/sum(sched_bal)*100,6),'%') end as "SMM"
	  , case when sum(sched_bal)>0 
	    then concat(format((1-power(1-sum(unsched_prin)/sum(sched_bal),12))*100,2),'%') end as "CPR"
	  , format(sum(MO_NET_LOSS),0) as "Monthly Net Loss"	  
	  , case when sum(current_upb)>0 
	    then concat(format(sum(D30)/sum(current_upb)*100,2),'%') end as "30DD%"	  
	  , case when sum(current_upb)>0 
	    then concat(format(sum(D60)/sum(current_upb)*100,2),'%') end as "60DD%"	  
	  , case when sum(current_upb)>0 
	    then concat(format(sum(D90PLUS)/sum(current_upb)*100,2),'%') end as "90+DD%"	  

_BYAGE_*/
/*_+CHAN_
, concat(format(sum(case when channel='B' then orig_upb end)/sum(orig_upb)*100,2),'%') as "Broker %"
, concat(format(sum(case when channel='C' then orig_upb end)/sum(orig_upb)*100,2),'%') as "Corresp. %"
, concat(format(sum(case when channel='R' then orig_upb end)/sum(orig_upb)*100,2),'%') as "Retail %"
_+CHAN_*/
/*_+GEO_
  -- selection of high speed states
, concat(format(sum(case when state='CA' then orig_upb end)/sum(orig_upb)*100,2),'%') as "CA%"
, concat(format(sum(case when state='AZ' then orig_upb end)/sum(orig_upb)*100,2),'%') as "AZ%"
, concat(format(sum(case when state='UT' then orig_upb end)/sum(orig_upb)*100,2),'%') as "UT%"
, concat(format(sum(case when state='CO' then orig_upb end)/sum(orig_upb)*100,2),'%') as "CO%"
, concat(format(sum(case when state='NV' then orig_upb end)/sum(orig_upb)*100,2),'%') as "NV%"
  -- selection of HPI/CREDIT states
, concat(format(sum(case when state='ID' then orig_upb end)/sum(orig_upb)*100,2),'%') as "ID%"
, concat(format(sum(case when state='FL' then orig_upb end)/sum(orig_upb)*100,2),'%') as "FL%"
, concat(format(sum(case when state='WY' then orig_upb end)/sum(orig_upb)*100,2),'%') as "WY%"
, concat(format(sum(case when state='TX' then orig_upb end)/sum(orig_upb)*100,2),'%') as "TX%"
, concat(format(sum(case when state='UT' then orig_upb end)/sum(orig_upb)*100,2),'%') as "MI%"
_+GEO_*/
/*_+STRT_
, concat(format(sum(case when high_balance_loan_indicator='Y' then orig_upb end)/sum(orig_upb)*100,2),'%') as "HBal%"
  -- credit characteristics
, concat(format(sum(case when occ_stat='S' then orig_upb end)/sum(orig_upb)*100,2),'%') as "2nd Home%"
, concat(format(sum(case when purpose='C' then orig_upb end)/sum(orig_upb)*100,2),'%') as "Cashout%"
, concat(format(sum(case when first_flag='Y' then orig_upb end)/sum(orig_upb)*100,2),'%') as "1st Home Buyer%"
, concat(format(sum(case when prop='CO' then orig_upb end)/sum(orig_upb)*100,2),'%') as "Condo%"
, concat(format(sum(case when NO_UNITS>=2 then orig_upb end)/sum(orig_upb)*100,2),'%') as "2+Fam%"
  -- credit metrics
, format(sum(orig_upb*oltv)/sum(case when oltv is not null then orig_upb end),1) as OLTV
, format(sum(orig_upb*ocltv)/sum(case when ocltv is not null then orig_upb end),1) as OCLTV
, format(sum(orig_upb*cscore_b)/sum(case when cscore_b is not null then orig_upb end),1) as "FICO"
, format(sum(orig_upb*cscore_c)/sum(case when cscore_c is not null then orig_upb end),1) as "Cob. FICO"
, format(sum(orig_upb*qfico)/sum(case when qfico is not null then orig_upb end),1) as "Qual. FICO"
, format(sum(orig_upb*dti)/sum(case when dti is not null then orig_upb end),1) as DTI

  -- eligibility results
, concat(format(sum(case when ELIGIBLE='N' then orig_upb end)/sum(orig_upb)*100,2),'%') as "MAP Inel.%"
_+STRT_*/
/*_+ELIG_
, concat(format(sum(case when OCC_STAT='I' then orig_upb end)/sum(orig_upb)*100,2),'%') as "Invest%"
, concat(format(sum(case when least(ifnull(cscore_c,999), cscore_b) < 640 then orig_upb end)/sum(orig_upb)*100,2),'%') as "FICO<640%"
, concat(format(sum(case when ifnull(OCLTV,ifnull(OLTV,100))>95 then orig_upb end)/sum(orig_upb)*100,2),'%') as "LTV>95"
, concat(format(sum(case when DTI>45 then orig_upb end)/sum(orig_upb)*100,2),'%') as "DTI>45"
, concat(format(sum(case when PROP='MH' then orig_upb end)/sum(orig_upb)*100,2),'%') as "MH%"
, concat(format(sum(case when STATE in ('PR,VI')  then orig_upb end)/sum(orig_upb)*100,2),'%') as "PR|VI%"
, concat(format(sum(case when ifnull(IO,'N') = 'Y' then orig_upb end)/sum(orig_upb)*100,2),'%') as "IO%"
, concat(format(sum(case when ifnull(PROPERTY_INSPECTION_WAIVER_INDICATOR,'A') <> 'A'then orig_upb end)/sum(orig_upb)*100,2),'%') as "Appr. not Full %"
, concat(format(sum(case when ifnull(PROPERTY_INSPECTION_WAIVER_INDICATOR,'A') = 'W'then orig_upb end)/sum(orig_upb)*100,2),'%') as "Appr. Waiv %"
, concat(format(sum(case when INEL_B3_FICO_LT_660='Y' then orig_upb end)/
  			 sum(orig_upb)*100,2),'%')		as "Inel FICO<660"
, concat(format(sum(case when INEL_B5_CASH_CONDO_2FAM_CLTV_LT90='Y' then orig_upb end)/
  			 sum(orig_upb)*100,2),'%')		as "Inel Cash,Condo,2fam,CLTV<90%"
, concat(format(sum(case when INEL_B6_CLTV_GT90='Y' then orig_upb end)/sum(orig_upb)*100,2),'%') as "Inel CLTV>90%"
_+ELIG_*/
/*_+STRT_
, concat(format(sum(case when SUBLIMIT_A_GT_85='Y' then orig_upb end)/sum(orig_upb)*100,2),'%') as "SUB A%"
, concat(format(sum(case when SUBLIMIT_B_75_85='Y' then orig_upb end)/sum(orig_upb)*100,2),'%') as "SUB B%"
  -- prepay performance 
_+STRT_*/
 /*_HIST_
, max(@pp_term) as "PP Horizon"
, format(sum(current_upb),0) as "Horiz Act"
, format(sum(horz_sched_upb),0) as "Horiz Sched"
, concat(format(100*(1-power(sum(current_upb)/sum(horz_sched_upb),12/@pp_term)),2),'%') as "Horiz CPR"
  -- credit performance
, max(@dq_term) as "DQ Horizon"
, concat(format(sum(ever_60P)/sum(orig_upb)*100,2),'%') as "Horiz Ever 60DD"
 _HIST_*/
/*_+STRT_  
, format(sum(case when ZERO_BAL_CODE in ('02','03','09','15')
  		  and DISPOSITION_DATE is not null then last_upb end),0) as "Defaulted UPB"
, concat(format(sum(case when ZERO_BAL_CODE in ('02','03','09','15')
  		  and DISPOSITION_DATE is not null then last_upb end)/sum(orig_upb)*100,2),'%') as "Default %"
, format(sum(NET_LOSS),0) as "Net Loss"	  
, concat(format(sum(NET_LOSS)/sum(orig_upb)*100,3),'%') as "Net Loss %"	  
_+STRT_*/
from
(
select substring(orig.orig_date,1,4) as vintage
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
,orig.prop
,orig.occ_stat
,orig.purpose
,orig.state
,orig.ppmt_flg
,orig.io
,orig.property_inspection_waiver_indicator
,orig.loan_term
 -- , orig.*
, least(ifnull(orig.cscore_c,999), orig.cscore_b) as QFICO
 /*_HIST_
 , case when hist.current_upb = 0 and hist.LOAN_AGE is not NULL then
   orig.orig_upb*
	(power(1+orig.orig_rate/1200,orig.orig_term)
	- power(1+orig.orig_rate/1200,hist.loan_age ))
	/(power(1+orig.orig_rate/1200,orig.orig_term)-1)
	   -- formula reference https://www.wallstreetmojo.com/mortgage-formula/
   else hist.current_upb end as CURRENT_UPB
 _HIST_*/
/*_BYSELL_  ,seller_rank  _BYSELL_*/
/*_BYSVCR_  ,servicer_rank  _BYSVCR_*/
/*_BYAGE_
 , case when hist.current_upb = 0 and hist.LOAN_AGE is not NULL then
   orig.orig_upb*
	(power(1+orig.orig_rate/1200,orig.orig_term)
	- power(1+orig.orig_rate/1200,hist.loan_age ))
	/(power(1+orig.orig_rate/1200,orig.orig_term)-1)
	   -- formula reference https://www.wallstreetmojo.com/mortgage-formula/
   else hist.current_upb end as CURRENT_UPB

, case when hist.LOAN_AGE is null then
  12*(substr(hist.ACT_PERIOD,1,4)-substr(hist.FIRST_PAY,1,4))+
  (substr(hist.ACT_PERIOD,5,2)-substr(hist.FIRST_PAY,5,2))+1
  else
  hist.LOAN_AGE end as LOAN_AGE
, case when hist.DLQ_STATUS='01' then
  case when hist.current_upb > 0 then
    hist.current_upb
  else
   orig.orig_upb*
	(power(1+orig.orig_rate/1200,orig.orig_term)
	- power(1+orig.orig_rate/1200,hist.loan_age ))
	/(power(1+orig.orig_rate/1200,orig.orig_term)-1) end else 0 end as D30
, case when hist.DLQ_STATUS='02' then
  case when hist.current_upb > 0 then
    hist.current_upb
  else
   orig.orig_upb*
	(power(1+orig.orig_rate/1200,orig.orig_term)
	- power(1+orig.orig_rate/1200,hist.loan_age ))
	/(power(1+orig.orig_rate/1200,orig.orig_term)-1) end else 0 end as D60
, case when hist.DLQ_STATUS>='03' then
  case when hist.current_upb > 0 then
    hist.current_upb
  else
   orig.orig_upb*
	(power(1+orig.orig_rate/1200,orig.orig_term)
	- power(1+orig.orig_rate/1200,hist.loan_age ))
	/(power(1+orig.orig_rate/1200,orig.orig_term)-1) end else 0 end as D90PLUS

  ,case when hist.ZERO_BAL_CODE>1 then greatest(0,
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
	else 0  end as MO_NET_LOSS
 -- PREPAYMENT
 -- , coalesce(hist.current_upb,0) as current_upb
 , case when hist.current_upb = 0 and hist.LOAN_AGE is not NULL then
   orig.orig_upb*
	(power(1+orig.orig_rate/1200,orig.orig_term)
	- power(1+orig.orig_rate/1200,hist.loan_age ))
	/(power(1+orig.orig_rate/1200,orig.orig_term)-1)
	   -- formula reference https://www.wallstreetmojo.com/mortgage-formula/
   when hist.current_upb = 0 and hist.LOAN_AGE is NULL then
   	hist.LAST_UPB
   else hist.current_upb end as SCHED_BAL
,  case when hist.ZERO_BAL_CODE = 01 then hist.LAST_UPB else 0 end as UNSCHED_PRIN
_BYAGE_*/

/*_+STRT_
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

 -- ,least(0,
 --	term.NET_SALES_PROCEEDS+term.CREDIT_ENHANCEMENT_PROCEEDS
 -- 	+term.REPURCHASES_MAKE_WHOLE_PROCEEDS+term.OTHER_FORECLOSURE_PROCEEDS
 --	-term.LAST_UPB-term.FORECLOSURE_COSTS-term.PROPERTY_PRESERVATION_AND_REPAIR_COSTS-term.ASSET_RECOVERY_COSTS
 --	-term.MISCELLANEOUS_HOLDING_EXPENSES_AND_CREDITS-term.ASSOCIATED_TAXES_FOR_HOLDING_PROPERTY) as NET_LOSS
_+STRT_*/

, case when orig.first_pay <= @pp_max_first_pay then -- only if seasoned beyond @pp_term months
       orig.orig_upb*(power(1+orig.orig_rate/1200,orig.orig_term)-power(1+orig.orig_rate/1200,@pp_term))/
	(power(1+orig.orig_rate/1200,orig.orig_term)-1) end as horz_sched_upb
 -- , case when orig.orig_term > 240 then 360
 -- when orig.orig_term > 180 then 240
 --  else 180 end as loan_term
,case when orig.OCC_STAT != 'I'
        and ifnull(orig.DTI,100) <=45
	and ifnull(orig.OCLTV,ifnull(orig.OLTV,100))<=95
        and least(ifnull(orig.cscore_c,999), orig.cscore_b) >= 640
        and orig.prop != 'MH'		     
        and orig.state not in ('PR','VI')
        and ifnull(orig.PPMT_FLG,'N') = 'N'
        and ifnull(orig.IO,'N') = 'N'
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
 /*_HIST_
, case when exists(select * from fncrt_sfloan dlqhist
       where orig.loan_id = dlqhist.loan_id  and dlqhist.dlq_status >='02' and dlqhist.loan_age<= @dq_term )
       then orig.orig_upb end as ever_60P
 -- , case when exists (select * from fncrt_sfloan dlqhist
 --      where orig.loan_id = dlqhist.loan_id and dlqhist.dlq_status >='04' and dlqhist.loan_age<= @dq_term )
 --      then orig.orig_upb end as ever_120P
 _HIST_*/
, term.FORECLOSURE_DATE
, term.DISPOSITION_DATE
,term.LAST_UPB
,term.LOAN_AGE as TERM_LOAN_AGE
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
( select
fnsf_origination.loan_id
,fnsf_origination.orig_date
,fnsf_origination.orig_term
,fnsf_origination.orig_rate
,fnsf_origination.orig_upb
,fnsf_origination.channel
,fnsf_origination.high_balance_loan_indicator
,fnsf_origination.first_flag
,fnsf_origination.first_pay
,fnsf_origination.seller
,fnsf_origination.servicer
,fnsf_origination.dti
,fnsf_origination.oltv
,fnsf_origination.ocltv
,fnsf_origination.cscore_b
,fnsf_origination.cscore_c
,fnsf_origination.no_units
,fnsf_origination.prop
,fnsf_origination.occ_stat
,fnsf_origination.purpose
,fnsf_origination.state
,fnsf_origination.ppmt_flg
,fnsf_origination.io
,fnsf_origination.property_inspection_waiver_indicator
, case when fnsf_origination.orig_term > 240 then 360
  when fnsf_origination.orig_term > 180 then 240
  else 180 end as loan_term

from
fnsf_origination
	where 1=1
       and substring(orig_date,1,4)>=@start_year
       and substring(orig_date,1,4)<=@end_year
      /*_TERM_ 
       and  _TERM_ = case when fnsf_origination.orig_term > 240 then 360
         when fnsf_origination.orig_term > 180 then 240
	   else 180 end
	_TERM_*/              
      /*_ST_ and state='_ST_'  _ST_*/ 
      /*_TOPST_
       and state in ('CA','TX','FL','MI', 'WA','CO','AZ','NY','VA','NJ','IL','NC','MA','GA','PA','MD','UT')  _TOPST_*/
      /*_TEST_ limit 1000 _TEST_*/
      /*_LIM_ limit _LIM_  _LIM_*/
) orig
/*_BYSELL_
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
_BYSELL_*/
/*_BYSVCR_
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
_BYSVCR_*/
/*_BYAGE_
LEFT JOIN
fncrt_sfloan hist -- historical prepay
	     on 1=1
   	     and orig.loan_id=hist.loan_id
	     and ((hist.loan_age is null) or (hist.loan_age >= 0))
_BYAGE_*/	     
 /*_HIST_
LEFT JOIN
fncrt_sfloan hist -- historical prepay
	     on 1=1
   	     and orig.loan_id=hist.loan_id
	     and hist.loan_age = @pp_term 
 _HIST_*/
LEFT JOIN
fnsf_terminal term -- terminal state
	      on orig.loan_id=term.loan_id
where 1=1
       and substring(orig.orig_date,1,4)>=@start_year
       and substring(orig.orig_date,1,4)<=@end_year
       /*_SELL_ and orig_seller.seller like 'Flagstar%' _SELL_*/
       /*_PRCH_ and orig.purpose='P'  _PRCH_*/
       /*_FILTER_*/
) loans
where 1=1
      /*_SELLN_ 
      and seller_rank >= _SELL0_ 
      and seller_rank <= _SELLN_  _SELLN_*/
      /*_ELIG_ and eligible = 'Y'       _ELIG_*/
      /*_ONLY30_ and loan_term = 360 _ONLY30_*/
      /*_TERM_ and loan_term=_TERM_ _TERM_*/
      /*_TOPST_
       and state in ('CA','TX','FL','MI', 'WA','CO','AZ','NY','VA','NJ','IL','NC','MA','GA','PA','MD','UT')  _TOPST_*/
group by loan_term
/*_BYVINT_ , vintage _BYVINT_*/
/*_BYST_ ,state _BYST_*/
/*_BYHBAL_ , high_balance_loan_indicator  _BYHBAL_*/
/*_BYFRST_ , first_flag _BYFRST_*/
/*_BYSELL_ , seller_rank  _BYSELL_*/
/*_BYSVCR_ , servicer_rank  _BYSVCR_*/
/*_BYCHAN_ , channel _BYCHAN_*/
/*_BYAGE_ ,  loan_age _BYAGE_*/
with rollup 
order by loan_term desc
/*_BYVINT_ , vintage _BYVINT_*/
/*_BYST_ , state _BYST_*/
/*_BYHBAL_ , grouping(high_balance_loan_indicator), high_balance_loan_indicator _BYHBAL_*/
/*_BYFRST_ ,  grouping(first_flag),first_flag _BYFRST_*/
/*_BYSELL_ ,grouping(seller_rank),-cast(seller_rank as unsigned) desc   _BYSELL_*/
/*_BYSVCR_ ,grouping(servicer_rank),-cast(servicer_rank as unsigned) desc   _BYSVCR_*/
/*_BYCHAN_ ,  grouping(channel), channel _BYCHAN_*/
/*_BYAGE_ , grouping(loan_age),loan_age _BYAGE_*/

;
