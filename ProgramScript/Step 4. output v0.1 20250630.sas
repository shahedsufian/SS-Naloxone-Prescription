
/*************************FINAL OUTPUT****************************/
/* Creates counts for prescriptions by each Provider type */
/*Output for "Providers" sheet*/
proc sql;
/* Creates counts for prescriptions by each Provider type */
	create table prov_rx_cnts as /*23*/
	select distinct 
		year,
		Provider_Type,
		count(distinct compress(studyid||PC026_DrugCode||put(PC032_DatePrescriptionFilled,date9.))) as numrxs
  	from ssdrive.prescribing_prov_names
 	group by year, Provider_Type
 	order by year, Provider_Type;
quit;

/*Transpose data*/
data ssdrive.Provider_Type;
set prov_rx_cnts;
by year Provider_Type;
retain Rx_by_State Rx_by_Other Rx_w_Missing_Prov;

if Provider_type= 'Missing' then Rx_w_Missing_Prov= numrxs;
else if Provider_type= 'Other' then Rx_by_Other= numrxs;
else Rx_by_State= numrxs;

if last.Year then
	do;
		keep Year Rx_by_State Rx_by_Other Rx_w_Missing_Prov;
		output;
	end;
run;

proc sql;
	create table ssdrive.provideroutput as
	select distinct 
		a.Year,
		b.Members_w_Rx,
		b.Total_narcan_Rx,
		a.Rx_by_State,
		a.Rx_by_Other,
		a.Rx_w_Missing_Prov
	from ssdrive.Provider_Type a
	left join	(
				select distinct
					year,
					count(distinct studyid) as Members_w_Rx,
					count(distinct compress(studyid||put(PC032_DatePrescriptionFilled,date9.)||PC026_DrugCode)) as Total_narcan_Rx
				from ssdrive.prescribing_prov_names
				group by year
				) b 
		on a.year = b.year;
quit;

libname xlout "G:\DATA\AAA Analytic Projects\Opioid Studies\2025\output\Narcan and Opioid Rxs &xlvers. .xlsx";
data xlout.providers;
set ssdrive.provideroutput;
run;
libname xlout;

/*macro to build output for columns B-F of "Prescriptions no MCRAdv" sheet */
%macro by_FY(first_fy,last_fy);
%do fy=&first_fy. %to &last_fy.;
	proc sql; 
	create table for_counts_&fy as /*17: 70; 18: 750; 19: 2,823; 20: 4,141; 21: 5,226; 22: 21,457; 23: 22,168; 24: 14,052*/
 	 select distinct count(distinct compress(put(PC032_DatePrescriptionFilled,date9.)||PC026_DrugCode)) as numRxs,
		  case
		    when missing(studyid) then newid
		    else studyid
		  end as studyid
  		from ssdrive.narcanclaims&fy.
  	group by calculated studyid
  	order by numRxs;
quit;
%end;

proc sql;
create table ssdrive.by_FY as
select distinct "FY&first_fy." as Rx_Dates, 
 		count(distinct studyid) as People  format=comma9., 
		sum(numRxs) as Tot_Narcan_Rx  format=comma9.,
		(select count(distinct Studyid) from for_counts_&first_fy. where numRxs= 1) as Narcan_1_Dose format=comma9.,
		(select count(distinct Studyid) from for_counts_&first_fy. where numRxs= 2) as Narcan_2_Dose format=comma9.,
		(select count(distinct Studyid) from for_counts_&first_fy. where numRxs= 3) as Narcan_3_Dose format=comma9.
	from for_counts_&first_fy.
%do fy=%eval(&first_fy.+1) %to &last_fy.;
union
select distinct "FY&fy." as Rx_Dates, 
 		count(distinct studyid) as People format=comma9., 
		sum(numRxs) as Tot_Narcan_Rx format=comma9.,
		(select count(distinct Studyid) from for_counts_&fy where numRxs= 1) as Narcan_1_Dose format=comma9.,
		(select count(distinct Studyid) from for_counts_&fy where numRxs= 2) as Narcan_2_Dose format=comma9.,
		(select count(distinct Studyid) from for_counts_&fy where numRxs= 3) as Narcan_3_Dose format=comma9.
	from for_counts_&fy.
%end;

order by Rx_Dates;
quit;

%mend by_FY;

%by_FY(17,24)

/*macro to build tables for columns G-P of "Prescriptions no MCRAdv" sheet */
%macro for_output(first_fy,last_fy);
proc sql;
create table ssdrive.by_FY_OP as
%do fy=%eval(&first_fy.) %to &last_fy.;
	%if &fy. ne &first_fy. %then union;
	select distinct "FY&fy." as Rx_Dates, 
	 		count(distinct studyid) as Mems_w_Op_Rx  format=comma9.,

			(select count(distinct Studyid) 
				from ssdrive.OPIOIDMEMRX_&fy.
				where highdose90mme= 1) as MME_90 format=comma9.,
			(select count(distinct Studyid) 
				from ssdrive.OPIOIDMEMRX_&fy.
				where highdose90mme= 1 and narcan_flag= 1) as MME_90_Narcan format=comma9.,
			(Calculated MME_90/calculated MME_90_Narcan) as Narcan_to_MME90_Ratio format=comma9.,		

			(select count(distinct Studyid) 
				from ssdrive.OPIOIDMEMRX_&fy.
				where highdose50mme= 1) as MME_50 format=comma9.,
			(select count(distinct Studyid) 
				from ssdrive.OPIOIDMEMRX_&fy.
				where highdose50mme= 1 and narcan_flag= 1) as MME_50_Narcan format=comma9.,
			(Calculated MME_50/calculated MME_50_Narcan) as Narcan_to_MME50_Ratio format=comma9.,

			(Calculated MME_50 - calculated MME_90) as MME50_to_90 format=comma9.,
			(Calculated MME_50_Narcan - calculated MME_90_Narcan) as MME50_to_90_Narcan format=comma9.,
			(calculated MME50_to_90/ calculated MME50_to_90_Narcan) as Narcan_to_MME50_to_90_Ratio  format=comma9.

		from ssdrive.OPIOIDMEMRX_&fy.
%end;
order by Rx_Dates;
quit;
%mend for_output;

%for_output(17,24)

/*combine tables to generate output for "Prescriptions no MCRAdv" sheet */
proc sql;
create table ssdrive.Prescriptionsoutput as
select distinct a.Rx_Dates,
				a.People,
				a.Tot_Narcan_Rx,
				a.Narcan_1_Dose,
				a.Narcan_2_Dose,
				a.Narcan_3_Dose,
				b.Mems_w_Op_Rx,
				b.MME_90,
				b.MME_90_Narcan,
				b.Narcan_to_MME90_Ratio,
				b.MME_50,
				b.MME_50_Narcan,
				b.Narcan_to_MME50_Ratio,
				b.MME50_to_90,
				b.MME50_to_90_Narcan,
				b.Narcan_to_MME50_to_90_Ratio
from ssdrive.by_FY a
inner join ssdrive.by_FY_OP b on a.RX_Dates = b.Rx_Dates
order by RX_Dates
;
quit; 

libname xlout "G:\DATA\AAA Analytic Projects\Opioid Studies\2025\output\Narcan and Opioid Rxs &xlvers. .xlsx";
data xlout.Prescriptions;
set ssdrive.Prescriptionsoutput;
run;
libname xlout;

/*quarterly*/
%macro by_Qtr(fy);
%do Qtr=1 %to 4;
	proc sql; 
	create table for_counts_Q&Qtr. as 
 	 select distinct count(distinct compress(put(PC032_DatePrescriptionFilled,date9.)||PC026_DrugCode)) as numRxs,
		  case
		    when missing(studyid) then newid
		    else studyid
		  end as studyid
  		from ssdrive.narcanclaims&fy.
		where quarter= "FY20&en_yr.Q&Qtr."
  	group by calculated studyid
  	order by numRxs;
quit;
%end;

proc sql;
create table ssdrive.by_Qtr as
select distinct "QTR_FY20&en_yr.Q1" as Rx_Dates, 
 		count(distinct studyid) as People  format=comma9., 
		sum(numRxs) as Tot_Narcan_Rx  format=comma9.
	from for_counts_Q1
%do Qtr=2 %to 4;
union
select distinct "QTR_FY20&en_yr.Q&Qtr." as Rx_Dates, 
 		count(distinct studyid) as People format=comma9., 
		sum(numRxs) as Tot_Narcan_Rx format=comma9.
	from for_counts_Q&Qtr.
%end;

order by Rx_Dates;
quit;
%mend by_Qtr;

%by_Qtr(24)

proc sql;
create table ssdrive.By_QTR_temp as 
select distinct cats("QTR_",a.quarter) as Rx_Dates, b.Opi_StudyID, c.HDO90_StudyID, 
		d.HDO50_StudyID, e.HDO50_to90_StudyID
	from ssdrive.FinalHDOFlags_&en_yr.Q a
		left join (select quarter,count(distinct studyid) as Opi_StudyID
						from ssdrive.FinalHDOFlags_&en_yr.Q
						group by quarter) b
			on a.quarter=b.quarter
		left join (select quarter,count(distinct studyid) as HDO90_StudyID
						from ssdrive.FinalHDOFlags_&en_yr.Q 
						where highdose90mme = 1
						group by quarter) c
			on a.quarter=c.quarter
		left join (select quarter,count(distinct studyid) as HDO50_StudyID
						from ssdrive.FinalHDOFlags_&en_yr.Q 
						where highdose50mme = 1
						group by quarter) d
			on a.quarter=d.quarter
		left join (select quarter,count(distinct studyid) as HDO50_to90_StudyID
						from ssdrive.FinalHDOFlags_&en_yr.Q 
						where highdose50mme = 1 and highdose90mme = 0
						group by quarter) e
			on a.quarter=e.quarter;
quit;

proc sql;
create table ssdrive.FY&en_yr.quarterlyoutput as
select distinct a.Rx_Dates
				,a.People as Mems_w_Narcan_Rx
				,a.Tot_Narcan_Rx
				,b.Opi_StudyID as Mems_w_Opioid_Rx
				,b.HDO90_StudyID
				,b.HDO50_StudyID
				,b.HDO50_to90_StudyID
	from ssdrive.by_Qtr a
	left join ssdrive.By_QTR_temp b on a.Rx_dates = b.Rx_Dates;
quit;

libname xlout "G:\DATA\AAA Analytic Projects\Opioid Studies\2025\output\Narcan and Opioid Rxs &xlvers. .xlsx";
data xlout.FY&en_yr.quarterly;
set ssdrive.FY&en_yr.quarterlyoutput;
run;
libname xlout;

/*counties*/
%macro combine_counts;
proc sql; 
create table ssdrive.OpioidbyCountycnts_20%eval(&st_yr.+1)_20&en_yr. as /*608*/
  select "FY20%eval(&st_yr.+1)" as year,* 
		from ssdrive.OpioidbyCountycnts_%eval(&st_yr.+1)
  %do i= %eval(&st_yr.+2) %to &en_yr.;
	union
  	select "FY20&i" as year,* 
		from ssdrive.OpioidbyCountycnts_&i.
  %end;
;
quit;
%mend combine_counts;

%combine_counts

libname xlout "G:\DATA\AAA Analytic Projects\Opioid Studies\2025\output\Narcan and Opioid Rxs &xlvers. .xlsx";
data xlout.counties;
set ssdrive.OpioidbyCountycnts_20%eval(&st_yr.+1)_20&en_yr.;
run;
libname xlout;

/*calculating total number of presciptions by FY for columns R and S in "Narcan and Opioid Rx Charts" sheet*/
%macro OP_by_FY(first_fy,last_fy);
%do fy=&first_fy. %to &last_fy.;
	proc sql; 
	create table OP_Rx_counts_&fy. as
 	 select distinct count(distinct compress(put(PC032_DatePrescriptionFilled,date9.)||PC026_DrugCode)) as numRxs,
			  case
			    when missing(studyid) then newid
			    else studyid
			  end as studyid
	  	from ssdrive.opioidclaims&fy.
	  	group by calculated studyid
	  	order by numRxs;
quit;
%end;

proc sql;
create table ssdrive.OP_Rx_counts_by_FY as
select distinct "FY&first_fy." as Rx_Dates, 
		sum(numRxs) as Tot_Opioid_Rx  format=comma9.
	from OP_Rx_counts_&first_fy.
%do fy=%eval(&first_fy.+1) %to &last_fy.;
union
select distinct "FY&fy." as Rx_Dates, 
		sum(numRxs) as Tot_Opioid_Rx  format=comma9.
	from OP_Rx_counts_&fy.
%end;

order by Rx_Dates;
quit;

%mend OP_by_FY;

%OP_by_FY(17,24)

libname xlout "G:\DATA\AAA Analytic Projects\Opioid Studies\2025\output\Narcan and Opioid Rxs &xlvers. .xlsx";
data xlout.charts;
set ssdrive.OP_Rx_counts_by_FY;
run;
libname xlout;

/*output for "Narcan_Prescribers_FY2024" sheet */
proc sql;
create table Prescribers_in_FY20&en_yr. as
select distinct Prescribing_Provider, 
				count(distinct compress(studyid||(put(PC032_DatePrescriptionFilled,date9.)))) as numrxs
from ssdrive.prescribing_prov_names
where year="FY20&en_yr." 
	and Prescribing_Provider is not missing
group by Prescribing_Provider
/*order by Prescribing_Provider*/
order by numrxs desc
;
quit;

libname xlout "G:\DATA\AAA Analytic Projects\Opioid Studies\2025\output\Narcan and Opioid Rxs &xlvers. .xlsx";
data xlout.Narcan_Prescribers_in_FY20&en_yr.;
set Prescribers_in_FY20&en_yr.;
run;
libname xlout;

*==== ====== ===== Now on to NWA specific output ==== ==== === =====;

/*Output for "Providers" sheet*/
proc sql;
/* Creates counts for prescriptions by each Provider type */
create table prov_rx_cnts as /*23*/
  select distinct year,Provider_Type,count(distinct compress(studyid||PC026_DrugCode||
         put(PC032_DatePrescriptionFilled,date9.))) as numrxs
  from  ssdrive.prescribing_prov_names
  where member_county in (&nwa_counties.)
  group by year,Provider_Type
  order by year,Provider_Type;
quit;

/*Transpose data*/
data Provider_Type;
set prov_rx_cnts;
by year Provider_Type;
retain Rx_by_State Rx_by_Other Rx_w_Missing_Prov;

if Provider_type= 'Missing' then Rx_w_Missing_Prov= numrxs;
else if Provider_type= 'Other' then Rx_by_Other= numrxs;
else Rx_by_State= numrxs;

if last.Year then
	do;
		keep Year Rx_by_State Rx_by_Other Rx_w_Missing_Prov;
		output;
	end;
run;

proc sql;
create table ssdrive.provideroutputnwa as
select distinct a.Year
				,b.Members_w_Rx
				,b.Total_narcan_Rx
				,a.Rx_by_State
				,a.Rx_by_Other
				,a.Rx_w_Missing_Prov
	from Provider_Type a
	left join (select distinct 	year,
				count(distinct studyid) as Members_w_Rx,
				count(distinct compress(studyid||put(PC032_DatePrescriptionFilled,date9.)
				||PC026_DrugCode)) as Total_narcan_Rx
				from ssdrive.prescribing_prov_names
				where member_county in (&nwa_counties.)
				group by year
			   ) b on a.year = b.year

;
quit;

libname xlout "G:\DATA\AAA Analytic Projects\Opioid Studies\2025\output\Narcan and Opioid NWA only Rxs &xlvers. .xlsx";
data xlout.Narcan_Prescribers_in_FY20&en_yr.;
set ssdrive.provideroutputnwa;
run;
libname xlout;

/*macro to build output for columns B-F of "Prescriptions no MCRAdv" sheet */
%macro by_FY(first_fy,last_fy);
%do fy=&first_fy. %to &last_fy.;
	proc sql; 
	create table for_counts_&fy as /*17: 86 18: 876 19: 3,019 20: 4,055*/
 	 select distinct count(distinct compress(put(PC032_DatePrescriptionFilled,date9.)||PC026_DrugCode)) as numRxs,
		  case
		    when missing(studyid) then newid
		    else studyid
		  end as studyid
  		from ssdrive.narcanclaims&fy.
		where member_county in (&nwa_counties.)
  	group by calculated studyid
  	order by numRxs;
quit;
%end;

proc sql;
create table by_FY_nwa as
select distinct "FY&first_fy." as Rx_Dates, 
 		count(distinct studyid) as People  format=comma9., 
		sum(numRxs) as Tot_Narcan_Rx  format=comma9.,
		(select count(distinct Studyid) from for_counts_&first_fy. where numRxs= 1) as Narcan_1_Dose format=comma9.,
		(select count(distinct Studyid) from for_counts_&first_fy. where numRxs= 2) as Narcan_2_Dose format=comma9.,
		(select count(distinct Studyid) from for_counts_&first_fy. where numRxs= 3) as Narcan_3_Dose format=comma9.
	from for_counts_&first_fy.
%do fy=%eval(&first_fy.+1) %to &last_fy.;
union
select distinct "FY&fy." as Rx_Dates, 
 		count(distinct studyid) as People format=comma9., 
		sum(numRxs) as Tot_Narcan_Rx format=comma9.,
		(select count(distinct Studyid) from for_counts_&fy where numRxs= 1) as Narcan_1_Dose format=comma9.,
		(select count(distinct Studyid) from for_counts_&fy where numRxs= 2) as Narcan_2_Dose format=comma9.,
		(select count(distinct Studyid) from for_counts_&fy where numRxs= 3) as Narcan_3_Dose format=comma9.
	from for_counts_&fy.
%end;

order by Rx_Dates;
quit;

%mend by_FY;

%by_FY(17,24)

/*macro to build tables for columns G-P of "Prescriptions no MCRAdv" sheet */
%macro for_output(first_fy,last_fy);
proc sql;
create table by_FY_OP_nwa as
%do fy=&first_fy. %to &last_fy.;
	%if &fy. ne &first_fy. %then union;
	select distinct "FY&fy." as Rx_Dates, 
	 		count(distinct studyid) as Mems_w_Op_Rx  format=comma9.,

			(select count(distinct Studyid)
				from ssdrive.OPIOIDMEMRX_&fy.
				where highdose90mme= 1 and county in (&nwa_counties.)) as MME_90 format=comma9.,
			(select count(distinct Studyid)
				from ssdrive.OPIOIDMEMRX_&fy.
				where highdose90mme= 1 and narcan_flag= 1 and county in (&nwa_counties.)) as MME_90_Narcan format=comma9.,
			(Calculated MME_90/calculated MME_90_Narcan) as Narcan_to_MME90_Ratio format=comma9.,		

			(select count(distinct Studyid) 
				from ssdrive.OPIOIDMEMRX_&fy.
				where highdose50mme= 1 and county in (&nwa_counties.)) as MME_50 format=comma9.,
			(select count(distinct Studyid) 
				from ssdrive.OPIOIDMEMRX_&fy.
				where highdose50mme= 1 and narcan_flag= 1 and county in (&nwa_counties.)) as MME_50_Narcan format=comma9.,
			(Calculated MME_50/calculated MME_50_Narcan) as Narcan_to_MME50_Ratio format=comma9.,

			(Calculated MME_50 - calculated MME_90) as MME50_to_90 format=comma9.,
			(Calculated MME_50_Narcan - calculated MME_90_Narcan) as MME50_to_90_Narcan format=comma9.,
			(calculated MME50_to_90/ calculated MME50_to_90_Narcan) as Narcan_to_MME50_to_90_Ratio  format=comma9.

	from ssdrive.OPIOIDMEMRX_&fy.
	where county in (&nwa_counties.)
%end;
order by Rx_Dates;
quit;
%mend for_output;

%for_output(17,24)

/*combine tables to generate output for "Prescriptions no MCRAdv" sheet */
proc sql;
create table ssdrive.prescriptionsoutput_nwa as
select distinct a.Rx_Dates,
				a.People,
				a.Tot_Narcan_Rx,
				a.Narcan_1_Dose,
				a.Narcan_2_Dose,
				a.Narcan_3_Dose,
				b.Mems_w_Op_Rx,
				b.MME_90,
				b.MME_90_Narcan,
				b.Narcan_to_MME90_Ratio,
				b.MME_50,
				b.MME_50_Narcan,
				b.Narcan_to_MME50_Ratio,
				b.MME50_to_90,
				b.MME50_to_90_Narcan,
				b.Narcan_to_MME50_to_90_Ratio
	from by_FY_nwa a
	inner join by_FY_OP_nwa b on a.RX_Dates = b.Rx_Dates
order by RX_Dates
;
quit; 

libname xlout "G:\DATA\AAA Analytic Projects\Opioid Studies\2025\output\Narcan and Opioid NWA only Rxs &xlvers. .xlsx";
data xlout.prescriptions;
set ssdrive.prescriptionsoutput_nwa;
run;
libname xlout;

/*Macro to generating table for "FY24 Quarterly" sheet*/
%macro by_Qtr(fy);
%do Qtr=1 %to 4;
	proc sql; 
	create table for_counts_Q&Qtr. as /*17: 86 18: 876 19: 3,019 20: 4,055*/
 	 select distinct count(distinct compress(put(PC032_DatePrescriptionFilled,date9.)||PC026_DrugCode)) as numRxs,
		  case
		    when missing(studyid) then newid
		    else studyid
		  end as studyid
  		from ssdrive.narcanclaims&fy.
		where quarter= "FY20&en_yr.Q&Qtr." 
			and member_county in (&nwa_counties.)
  	group by calculated studyid
  	order by numRxs;
quit;
%end;

proc sql;
create table by_Qtr_nwa as
select distinct "QTR_FY20&en_yr.Q1" as Rx_Dates, 
 		count(distinct studyid) as People  format=comma9., 
		sum(numRxs) as Tot_Narcan_Rx  format=comma9.
	from for_counts_Q1
%do Qtr=1 %to 4;
union
select distinct "QTR_FY20&en_yr.Q&Qtr." as Rx_Dates, 
 		count(distinct studyid) as People format=comma9., 
		sum(numRxs) as Tot_Narcan_Rx format=comma9.
	from for_counts_Q&Qtr.
%end;

order by Rx_Dates;
quit;
%mend by_Qtr;

%by_Qtr(&en_yr)

/* copied from step 2 to adapt it to create "ssdrive.By_QTR_temp" table*/

proc sql;
create table By_QTR_temp_nwa as 
select distinct cats("QTR_",a.quarter) as Rx_Dates, b.Opi_StudyID, c.HDO90_StudyID, 
		d.HDO50_StudyID, e.HDO50_to90_StudyID
	from ssdrive.FinalHDOFlags_&en_yr.Q a
		left join (select quarter,count(distinct studyid) as Opi_StudyID
						from ssdrive.FinalHDOFlags_&en_yr.Q
						where member_county in (&nwa_counties.)
						group by quarter) b
			on a.quarter=b.quarter
		left join (select quarter,count(distinct studyid) as HDO90_StudyID
						from ssdrive.FinalHDOFlags_&en_yr.Q 
						where highdose90mme = 1 and member_county in (&nwa_counties.)
						group by quarter) c
			on a.quarter=c.quarter
		left join (select quarter,count(distinct studyid) as HDO50_StudyID
						from ssdrive.FinalHDOFlags_&en_yr.Q 
						where highdose50mme = 1 and member_county in (&nwa_counties.)
						group by quarter) d
			on a.quarter=d.quarter
		left join (select quarter,count(distinct studyid) as HDO50_to90_StudyID
						from ssdrive.FinalHDOFlags_&en_yr.Q 
						where highdose50mme = 1 and highdose90mme = 0 and member_county in (&nwa_counties.)
						group by quarter) e
			on a.quarter=e.quarter;
quit;

/*Generating output table for "FY24 Quarterly" sheet*/
proc sql;
create table ssdrive.fy&en_yr.quarterlyoutput_nwa as
select distinct a.Rx_Dates
				,a.People as Mems_w_Narcan_Rx
				,a.Tot_Narcan_Rx
				,b.Opi_StudyID as Mems_w_Opioid_Rx
				,b.HDO90_StudyID
				,b.HDO50_StudyID
				,b.HDO50_to90_StudyID
	from by_Qtr_nwa a
	left join By_QTR_temp_nwa b on a.Rx_dates = b.Rx_Dates;
quit;

libname xlout "G:\DATA\AAA Analytic Projects\Opioid Studies\2025\output\Narcan and Opioid NWA only Rxs &xlvers. .xlsx";
data xlout.fy&en_yr.quarterlyoutput_nwa;
set ssdrive.fy&en_yr.quarterlyoutput_nwa;
run;
libname xlout;

/*Counties sheet*/

%macro combine_counts;
proc sql; 
create table ssdrive.OpioidbyCountycnts_20%eval(&st_yr.+1)_20&en_yr._nwa as /*532*/
  select "FY20%eval(&st_yr.+1)" as year,* 
		from ssdrive.OpioidbyCountycnts_%eval(&st_yr.+1)
		where county in (&nwa_counties.)
  %do i= %eval(&st_yr.+2) %to &en_yr.;
	union
  	select "FY20&i" as year,* 
		from ssdrive.OpioidbyCountycnts_&i.
		where county in (&nwa_counties.)
  %end;
;
quit;
%mend combine_counts;

%combine_counts

libname xlout "G:\DATA\AAA Analytic Projects\Opioid Studies\2025\output\Narcan and Opioid NWA only Rxs &xlvers. .xlsx";
data xlout.counties;
set ssdrive.OpioidbyCountycnts_20%eval(&st_yr.+1)_20&en_yr._nwa;
run;
libname xlout;

/*calculating total number of presciptions by FY for columns R and S in "Narcan and Opioid Rx Charts" sheet*/
%macro OP_by_FY(first_fy,last_fy);
%do fy=&first_fy. %to &last_fy.;
	proc sql; 
	create table OP_Rx_counts_&fy._nwa as 
 	 select distinct count(distinct compress(put(PC032_DatePrescriptionFilled,date9.)||PC026_DrugCode)) as numRxs,
		  case
		    when missing(studyid) then newid
		    else studyid
		  end as studyid
  		from ssdrive.opioidclaims&fy.
		where member_county in (&nwa_counties.)
  	group by calculated studyid
  	order by numRxs;
quit;
%end;

proc sql;
create table OP_Rx_counts_by_FY_nwa as
select distinct "FY&first_fy." as Rx_Dates, 
		sum(numRxs) as Tot_Opioid_Rx  format=comma9.
	from OP_Rx_counts_&first_fy._nwa
%do fy=%eval(&first_fy.+1) %to &last_fy.;
union
select distinct "FY&fy." as Rx_Dates, 
		sum(numRxs) as Tot_Opioid_Rx  format=comma9.
	from OP_Rx_counts_&fy._nwa
%end;

order by Rx_Dates;
quit;

%mend OP_by_FY;

%OP_by_FY(17,24)

libname xlout "G:\DATA\AAA Analytic Projects\Opioid Studies\2025\output\Narcan and Opioid NWA only Rxs &xlvers. .xlsx";
data xlout.charts;
set OP_Rx_counts_by_FY_nwa;
run;
libname xlout;

/*output for "Narcan_Prescribers_FY2024" sheet */
proc sql;
create table Prescribers_in_FY20&en_yr._nwa as
select distinct Prescribing_Provider, 
				count(distinct compress(studyid||(put(PC032_DatePrescriptionFilled,date9.)))) as numrxs
	from ssdrive.prescribing_prov_names
	where year="FY20&en_yr." 
		and member_county in (&nwa_counties.)
		and Prescribing_Provider is not missing
	group by Prescribing_Provider
	/*order by Prescribing_Provider*/
	order by numrxs desc
;
quit;

libname xlout "G:\DATA\AAA Analytic Projects\Opioid Studies\2025\output\Narcan and Opioid NWA only Rxs &xlvers. .xlsx";
data xlout.narcan_prescribers;
set Prescribers_in_FY20&en_yr._nwa;
run;
libname xlout;
