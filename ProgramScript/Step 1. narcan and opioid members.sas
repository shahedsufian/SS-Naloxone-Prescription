/****************************************************************************************************************************************************
*                                                                                                                                                   *
* PURPOSE: To investigate the co-prescribing Naloxone/Narcan and high dose opioid prescriptions.                                                    *
*         	To Build member table														*
* 
* Date: 17 Jun 2025                                                                                                                                *
*                                                                                                                                                   *
*    v0.1 																																		*
*                                                                                                                                                   *
* PROJECT: Opioid Studies                                                                                                                           *
*                                                                                                                                                   *
****************************************************************************************************************************************************/

%macro load_data; /*this takes ~ time*/
/*14,212,174*/
	proc sql;
	create table ssdrive.StudyPharmclmsN as 
	select distinct 
		&keep_vars_sql.,
		compress(PC001_Submitter||PC107_CarrierSpecificUniqueMembe) as newid
	from apcd.apcd_pharm&apcdvers.20&st_yr.
	where PC032_DatePrescriptionFilled ge &start_1. and ((substr(PC026_DrugCode,1,9) in (&narcan_ndc_list.))
				/*this is different because we care about start date in the first year only*/
		or (PC026_DrugCode in (select ndc from opioid_ndc_info)))
	%do i= %eval(&st_yr.+1) %to &en_yr.;
		%if &i.= &en_yr. %then %do;
			union
			select distinct &keep_vars_sql.,
				compress(PC001_Submitter||PC107_CarrierSpecificUniqueMembe) as newid
			from apcd.apcd_pharm&apcdvers.20&i.
			where PC032_DatePrescriptionFilled le &stop_1. and ((substr(PC026_DrugCode,1,9) in (&narcan_ndc_list.))
				/*this is different because we care about stop date in the last year only*/
				or (PC026_DrugCode in (select ndc from opioid_ndc_info)))
		%end;
		%else %do;
			union
			select distinct &keep_vars_sql.,
				compress(PC001_Submitter||PC107_CarrierSpecificUniqueMembe) as newid
			from apcd.apcd_pharm&apcdvers.20&i.
			where ((substr(PC026_DrugCode,1,9) in (&narcan_ndc_list.))
				or (PC026_DrugCode in (select ndc from opioid_ndc_info)))
		%end;
	%end;
	;
	quit;
%mend load_data;

%load_data

/*data testclms;
set ssdrive.StudyPharmclmsN;
	if substr(newid,1,5) in ("99CAR") 
		then newid = compress(PC001_Submitter||PC107_CarrierSpecificUniqueMembe||PC012_MemberGender
								||put(PC013_MemberDateOfBirth,date9.));
	if substr(newid,1,5)="67369" 
		then newid = compress(PC001_Submitter||substr(PC107_CarrierSpecificUniqueMembe,1,10)
								||put(PC013_MemberDateOfBirth,date9.));
	if substr(newid,1,5)="99HSM"
		then newid = compress(PC001_Submitter||PC006_InsuredGroupNumberOrPolicy||"-"||PC107_CarrierSpecificUniqueMembe);
run;*/

Data ssdrive.allclmsqrtrs;  /*14,212,174*/
set ssdrive.StudyPharmclmsN;
	if substr(newid,1,5) in ("99CAR") 
		then newid = compress(PC001_Submitter||PC107_CarrierSpecificUniqueMembe||PC012_MemberGender
								||put(PC013_MemberDateOfBirth,date9.));
	if substr(newid,1,5)="67369" 
		then newid = compress(PC001_Submitter||substr(PC107_CarrierSpecificUniqueMembe,1,10)
								||put(PC013_MemberDateOfBirth,date9.));
	if substr(newid,1,5)="99HSM"
		then newid = compress(PC001_Submitter||PC006_InsuredGroupNumberOrPolicy||"-"||PC107_CarrierSpecificUniqueMembe);

	if substr(PC026_DrugCode,1,9) in (&narcan_ndc_list.) then narcan = 1;
		else narcan = 0;

	do yr=&st_yr. to  %eval(&en_yr. -1);
		if mdy(7,1,yr) le PC032_DatePrescriptionFilled le mdy(6,30,yr+1) then do;
			year= cat("FY20",put(sum(yr,1),2.));
			leave;
		end;
	end;

	if "01JUL20%eval(&en_yr. - 1)"d le PC032_DatePrescriptionFilled le "30SEP20%eval(&en_yr. - 1)"d 
		then quarter= "FY20&en_yr.Q1";
	else if "01OCT20%eval(&en_yr. - 1)"d le PC032_DatePrescriptionFilled le "31DEC20%eval(&en_yr. - 1)"d 
		then quarter= "FY20&en_yr.Q2";
	else if "01JAN20&en_yr."d le PC032_DatePrescriptionFilled le "31MAR20&en_yr."d 
		then quarter= "FY20&en_yr.Q3";
	else if "01APR20&en_yr."d le PC032_DatePrescriptionFilled le "30JUN20&en_yr."d 
		then quarter= "FY20&en_yr.Q4";

	partndc= substr(PC026_DrugCode,1,9);
	drop yr;
run;

/*members!! It will be member, change to it.*/
%macro mems (fy);

	%let yr = %eval(&fy. - 1);
/*	%let ds = ssdrive.NarcanEligible&fy.;*/
	%let start = "01JUL20&yr."d;
	%let stop = "30JUN20&fy."d;

	/****** Get the enrollment records for Narcan ******/
	proc sql;
	create table ssdrive.memsEligible&fy. as 
			/*FY 17:2,097,537; 18:2,295,620; 19:2,223,566; 20:2,197,199; 21:2,234,204; 22:2,119,895; 23:2,134,918; 24:1,729,492*/
		select distinct compress(ME001_Submitter||ME107_CarrierSpecificUniqueMembe) as newid,
				compress(ME998_APCDUniqueId||ME013_MemberGender||put(ME014_MemberDateOfBirth,date9.)) as studyid,
				&mem_varis
		  	from apcd.apcd_member&apcdvers.
			where calculated newid in (select distinct newid 
										from ssdrive.allclmsqrtrs 
										where year = "FY20&fy")
				and substr(calculated newid,1,5) not in ("67369", "99HSM", "99CAR")
	union
		select distinct compress(ME001_Submitter||ME107_CarrierSpecificUniqueMembe||ME013_MemberGender||put(ME014_MemberDateOfBirth,date9.)) as newid,
			compress(ME998_APCDUniqueId||ME013_MemberGender||put(ME014_MemberDateOfBirth,date9.)) as studyid,
			&mem_varis
	  	from apcd.apcd_member&apcdvers.
		where  substr(calculated newid,1,5) in ("99CAR")
			and calculated newid in (select distinct newid 	
										from ssdrive.allclmsqrtrs 
										where year = "FY20&fy")
	union
		select distinct compress(ME001_Submitter||substr(ME107_CarrierSpecificUniqueMembe,1,10)
					||put(ME014_MemberDateOfBirth,date9.)) as newid,
			compress(ME998_APCDUniqueId||ME013_MemberGender||put(ME014_MemberDateOfBirth,date9.)) as studyid,
			&mem_varis
		from apcd.apcd_member&apcdvers.
		where substr(calculated newid,1,5)="67369"
			and calculated newid  in (select distinct newid 	
										from ssdrive.allclmsqrtrs 
										where year = "FY20&fy")
	union
		select distinct compress(ME001_Submitter||ME107_CarrierSpecificUniqueMembe) as newid,
			compress(ME998_APCDUniqueId||ME013_MemberGender||put(ME014_MemberDateOfBirth,date9.)) as studyid,
			&mem_varis
		from apcd.apcd_member&apcdvers.
		where substr(calculated newid,1,5)="99HSM"
			and calculated newid  in (select distinct newid 	
										from ssdrive.allclmsqrtrs 
										where year = "FY20&fy")
		order by newid, PeriodEndingDate, ME162A_DateOfFirstEnrollment;
	;

	proc sql;
	title "Studyid vs Newid counts FY&fy.";
	select distinct count(distinct studyid) 
		from ssdrive.memsEligible&fy.; 
			/*FY 17:490,218; 18:450,149; 19:410,375; 20:378,943; 21:382,171; 22:365,474; 23:380,072; 24:326,797*/
	select distinct count(distinct newid) 
		from ssdrive.memsEligible&fy.; 
			/*FY 17:540,926 18:534,985; 19:477,569; 20:461,298; 21:468,344; 22:457,148; 23:470,510; 24:402,075*/
	quit;
	title;

	/*separating out for county info*/
	data addcounty&fy.; 
			/*FY 17:2,036,812; 18:2,245,216; 19:2,181,875; 20:2,158,983; 21:2,195,065; 22:2,082,511; 23:2,092,618*/
		length zipcode $5 fips_code Clean_County $50 ;
		if _n_=1 then 
			do;
				declare hash zip_to_county(dataset: "geo.CLEAN_COUNTY_XWALK");
				zip_to_county.definekey("zipcode");
				zip_to_county.definedata("Clean_County");
				zip_to_county.definedone();

				declare hash fips_to_county(dataset: "geo.CLEAN_COUNTY_XWALK");
				fips_to_county.definekey("fips_code");
				fips_to_county.definedata("Clean_County");
				fips_to_county.definedone();
			end;
		set ssdrive.memsEligible&fy.;
		where ME162A_DateOfFirstEnrollment le &stop_1. and ME163A_DateOfDisenrollment ge &start_1.;

		if ME016_MemberStateOrProvince= "05" 
			then rc1= fips_to_county.find(key: ME173A_MemberCounty);

		if rc1 gt 0 and not missing(ME017_MemberZipCode) 
			then rc2= zip_to_county.find(key: substr(ME017_MemberZipCode,1,5));

		drop zipcode fips_code rc1 rc2 ;
	run;

	data for_county_info&fy.; 
		/*FY 17:533,962; 18:527,236; 19:471,858 20:455,443; 21:463,339; 22:453,334; 23:466,778; 24:400,008*/
	set addcounty&fy.;
	where not missing(clean_county) and ME162A_DateOfFirstEnrollment le "30Jun20&fy."d 
		and ME163A_DateOfDisenrollment ge "01Jul20%eval(&fy.-1)"d ;
	  by newid PeriodEndingDate ME162A_DateOfFirstEnrollment;
	  if last.newid then do;  /*Selecting only most recent record*/
	  	keep newid clean_county ;
		output;
	  end;
	run;

	data ssdrive.memsElig_fy&fy.; 
		/*FY 17:540,926; 18:534,985; 19:477,569 20:461,298; 21:468,344; 22:457,148; 23:470,510; 24:402,075*/
	  set ssdrive.memsEligible&fy.;  
	  by newid PeriodEndingDate ME162A_DateOfFirstEnrollment;
	  if last.newid then output; /*Selecting only most recent record*/
	run;

	/****** This determines the number of peeps by coverage for a certain month ******/
	proc sql;
	create table temp_APCD_&fy. as 
		/*FY 17:1,311,394; 18:1,219,243; 19:1,015,183; 20:991,675; 21:1,009,172; 22:974,082 (780 missing studyid); 23:971,413; 24:710,009. Each datasets has observations with missing studyid.*/
	  select distinct b.studyid,b.ME173A_MemberCounty, a.*,c.clean_county as mem_county
	  from ssdrive.allclmsqrtrs a 
	left join ssdrive.memsElig_fy&fy. b  on a.newid = b.newid
	left join for_county_info&fy. c on a.newid = c.newid
	 
	  /*code below excludes Medicare*/
	  where &start. le a.PC032_DatePrescriptionFilled le &stop.
	and a.PC003_InsuranceType_ProductCode not in ('HN','HS','MCR','MA','MB','MD','MDV','MH',
	        'MHO','MI','MPO');
	quit;

	/*the idea here is to use zipcode on claims record to id county and then supplement with member county info - which 
	is their residence at the end of the fiscal year*/
	data ssdrive.ScriptsAPCD_fy&fy.; 
		/*FY 17:1,311,394; 18:1,219,243; 19:1,015,083; 20:991,675 21:1,009,172; 22:974,082; 23:971,413; 24:710,009*/
	length zipcode $5 Clean_County $50 ;
	if _n_=1 then 
		do;
			declare hash zip_to_county(dataset: "geo.CLEAN_COUNTY_XWALK");
			zip_to_county.definekey("zipcode");
			zip_to_county.definedata("Clean_County");
			zip_to_county.definedone();
		end;
	set temp_APCD_&fy.;

	if not missing(PC016_MemberZipCode) then rc1= zip_to_county.find(key: substr(PC016_MemberZipCode,1,5));
	member_county= coalescec(clean_county,mem_county);

	drop zipcode rc1 ;
	run;

%mend mems;

%mems(17); 
%mems(18); 
%mems(19); 
%mems(20); 
%mems(21); 
%mems(22); 
%mems(23); 
%mems(24); 
