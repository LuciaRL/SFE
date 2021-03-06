/* -----------------------------------------------------------------------------

     WFP - Policy and Programme Division - Analysis & Trends Service 
		   Economic and Market Analysis Unit 
		   
     CONTACT: Lucia Latino 
			  lucia.latino@wfp.org
			  Latino@Economia.uniroma2.it
      
	 AIM: generate the historical cost of food baskets for each country 
     
   
----------------------------------------------------------------------------- */



*** Clear environment 
	clear
	set more off

	use $path/output/data_all_clean.dta
			
	gen price_g=price/1000
	
	drop if price_g==. & Notes!="no price data available"
	
	gen total_cal=2100
		
	gen kcal=total_cal*fao_fct_kcalshare/100
	label var kcal "kcal/day/person from cm_name"
		
	gen qt_edible=kcal/cm_kcal_100g*100
	label var qt_edible "g/person/day from cm_name"
	
	gen qt=qt_edible+(qt_edible*refuse)
	label var qt "g/person/day from cm_name"

	gen cost=qt*price_g*30.5
	label var cost "national currency/person/month for cm_name"
	
	drop if cost==. &  Notes!="no price data available"
		
*** find the minimum calorie content for the food basket of each country
	* NOTE: time cut off should be changed by x month forward when updated is done in next x months
	bys adm0_id t: egen calorie=total(fao_fct_kcalshare)
	replace calorie=round(calorie, 3)
	gen l_cal=.
	
	levelsof adm0_id if  Notes!="no price data available", local (country)
	foreach num of numlist `country'  {
		local i = 1
		while `i'<40 { // older observations are dropped to allow for a basket covering at least 40% of daily caloric intake
			sum t if calorie==`i' & adm0_id==`num'
			gen l_time=r(max) if adm0_id==`num'
			drop if t<=l_time & l_time<=tm(2011, 6) & adm0_id==`num'  // NOTE: time cut off should be changed by x month forward when updated is done in next x months
			egen l_cal_`num'=min(calorie) if adm0_id==`num'
			
			tempvar check
			gen `check'=1 if adm0_id==`num' & (l_time<=tm(2011, 6) | l_time==.) // NOTE: time cut off should be changed by x month forward when updated is done in next x months
			replace `check'=2 if adm0_id==`num' & l_time>tm(2011, 6) & l_time!=. // NOTE: time cut off should be changed by x month forward when updated is done in next x months
			levelsof `check' , local(g)
				if  `g'==1 {
					levelsof l_cal_`num' if adm0_id==`num' & (l_time<=tm(2011, 6) | l_time==.), local(i) // NOTE: time cut off should be changed by x month forward when updated is done in next x months
				}
				else {
					local i = 200
				}
				display `i'
				drop l_time l_cal_`num'
		}	
		
	* if the use of last five years of data only allows for a higher caloric content of the basket, older observations are dropped
		sum calorie if adm0_id==`num'
		replace l_cal=r(min) if adm0_id==`num'
		
		sum calorie if adm0_id==`num' & t>=tm(2011, 7) // NOTE: time cut off should be changed by x month forward when updated is done in next x months
		local min=r(min)
		levelsof l_cal if adm0_id==`num', local (c)
		while `c'<`min' {
			sum calorie if adm0_id==`num' & t>=tm(2011, 7) // NOTE: time cut off should be changed by x month forward when updated is done in next x months
			sum t if calorie==r(min) & adm0_id==`num'
			gen l_time=r(min) if adm0_id==`num'
			drop if adm0_id==`num' & t<l_time  & t<tm(2011, 7) // NOTE: time cut off should be changed by x month forward when updated is done in next x months
			sum calorie if adm0_id==`num'
			replace l_cal=r(min) if adm0_id==`num'
			drop l_time
			levelsof l_cal if adm0_id==`num', local (d)
			if `d'<`min'{
				sum t if adm0_id==`num' & l_cal==calorie
				gen l_time=r(max) if adm0_id==`num'
				drop if adm0_id==`num' & t<=l_time & t<tm(2011, 7) // NOTE: time cut off should be changed by x month forward when updated is done in next x months 
				drop l_time
			}
			levelsof l_cal if adm0_id==`num', local (c)
			sum calorie if adm0_id==`num' & t>=tm(2011, 7) // NOTE: time cut off should be changed by x month forward when updated is done in next x months
			local min=r(min)
		}
	}

	encode fao_fct_name, gen(food_gr)

*** the following group of commands avoids that there will be substitutions between commodities of different groups across time 
	levelsof food_gr, local(name)
	egen tag=tag(adm0_id t)
	bys adm0_id: egen count_time=count(tag) if tag
	bys adm0_id: egen obs=mean(count_time)
	drop tag count
	foreach n of local name {
		egen tag_`n'=tag(adm0_id food_gr t) if food_gr==`n'
		bys adm0_id: egen count_`n'=count(tag_`n') if tag_`n'
		bys adm0_id: egen mean_`n'=mean(count_`n')
		drop tag count
		drop if food_gr==`n' & mean_`n'<obs
	}

	drop mean_* obs l_cal
	bys adm0_id t: egen l_cal=total(fao_fct_kcalshare)
	
*** generate the time series for the cost of food basket 	
	gsort adm0_id t -fao_fct_k fao_fct_name
	by adm0_id t: gen basket=sum(fao_fct_kcalshare) 		
	bys adm0_id t: egen food_basket=total(cost) if basket<=l_cal
	label var food_basket "cost of the food basket - national currency/person/month"
	rename l_cal basket_kcal_share
	label var basket_kcal_share "share of kcal per food basket"
	
*** obtain and save in excel the food basket's details
	egen data=max(t)
	gen last_data= string(data, "%tmMonth_ccyy")

preserve
	replace adm0_name="State of Palestine" if adm0_id==999
	drop if food_basket==. | food_basket==0
	
	sort series t
	egen   start_date = min(t), by (series)
	egen   end_date   = max(t), by (series)
	format %tmMon-yy t start_date end_date
	gen 	month_cover = end_date - start_date +1
	
	bys series: egen data_count = count(price) 
	gen gap=1-(data_count/month_cover)

	replace cm_name=cm_name_F if cm_name==""
	duplicates drop adm0_name cm_name series pt start_date end_date, force
	
	gen price_type="retail" if pt==15
	replace price_type="wholesale" if pt==14
	replace price_type="producer" if pt==17
	replace price_type="farm gate" if pt==18
	
	keep adm0_name cm_name fao_fct_name start_date end_date basket_kcal_share fao_fct_kcalshare national data_sour price_type Notes last_
	rename adm0_name Country
	rename cm_name commodity
	rename fao_fct_name food_group
	rename fao_fct_kcalshare commodity_kcalshare
	
	gsort Country -commodity_kcalshare
	
	egen tag=tag(Cou)
	replace Country="" if tag==0
	replace basket_kcal=. if tag==0
	drop tag
	
	order Country basket_kcal_share commodity commodity_kcalshare price_type food_group start_date end_date Notes 
	export excel using $path/output/DCoS.xlsx, sheet("annex I - basket") sheetreplace firstrow(varia) cell (A7)
	putexcel set $path/output/DCoS.xlsx, sheet("annex I - basket") modify
	putexcel (A7:P7), bold hcenter vcenter font(Calibri, 11, darkblue) 
	putexcel (A7:A500), bold  font(Calibri, 11)	
	putexcel (B2:D500), nformat(number)
	putexcel A1="WFP - VAM/Economic and Market Analysis Unit", bold  vcenter font(Calibri, 14, blue)
	putexcel A3="Food Basket Composition", bold  vcenter font(Calibri, 11, darkblue)
	local today=c(current_date)
	local data=last_data[1]
	putexcel A4="last update: `today' --- last prices used are from `data'" , italic font(Calibri, 11)
restore	

** obtain data for the tableau visualization
preserve 
	replace adm0_name="State of Palestine" if adm0_id==999
	duplicates drop adm0_id fao_fct_name, force
	bys adm0_id: gen toexpand=_n == _N
	expand 2 if toexpand
	keep adm0_id adm0_name fao_fct_name fao_fct_kcalshare total_cal basket_kcal_share last_data 
	egen tag=tag(adm0_id adm0_name fao_fct_name fao_fct_kcalshare total_cal basket_kcal_share last_data) 
	replace fao_fct_name="Not available" if tag==0
	replace fao_fct_kcalshare=100-basket_kcal_share if tag==0
	drop tag
	export excel using "C:\Users\lucia.latino\Documents\2.Market_team\DCoS\tableau\tableau.xlsx", sheet("basket") sheetreplace firstrow(varia)
restore
 	
	egen keep=tag(adm0_id time) if food_basket!=. 
	
	keep if keep |  Notes=="no price data available"
	
	keep adm0_name adm0_id t* food_basket cur* basket_kcal_share Notes
		
	sort adm0_id time
	
	save $path/output/basket.dta, replace
	
