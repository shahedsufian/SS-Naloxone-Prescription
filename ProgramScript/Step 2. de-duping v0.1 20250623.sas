/****************************************************************************************************************************************************
*                                                                                                                                                   *
* PURPOSE: To investigate the co-prescribing Naloxone/Narcan and high dose opioid prescriptions.                                                    *
*         	De-duping claims														*
* 
* Date: 23 Jun 2025                                                                                                                                *
*                                                                                                                                                   *
*    v0.1 																																		*
*                                                                                                                                                   *
* PROJECT: Opioid Studies                                                                                                                           *
*                                                                                                                                                   *
****************************************************************************************************************************************************/

%let fy = 22;

/*simple de-dup! do not care about payer or costs-- need MME and script count*/
proc sql;
create table fordedup&fy. as 
	/*17:1,311,394; 18:1,219,243; 19:1,015,183; 20:991,675; 21:1,009,172; 22:974,082; 23:971,413; 24: 710,009*/
select distinct 
		case
			when studyid is missing then newid /*from old method*/
			else studyid
		end as studyid,
		*,
		compress(calculated studyid||PC021_NationalProviderIDNumber_S||put(PC032_DatePrescriptionFilled,date9.)||PC026_DrugCode) as Dup_ID,
		case
			when pc001_submitter = "99CAR1" then 1
			when pc001_submitter = "99MCD1" then 3
			else 2
		end as subm_hier
	from SSDRIVE.SCRIPTSAPCD_FY&fy.
	order by dup_id, subm_hier ;
quit;

data dedupclaims&fy.; 
	/*17:1,253,991; 18:1,077,604 19:885,370; 20:826,870; 21:821,294; 22:784,395; 23:774,192; 24: 579,878*/
set fordedup&fy.;
by dup_id;
if first.dup_id;
run;

data ssdrive.opioidclaims&fy. ssdrive.narcanclaims&fy. ; 
set dedupclaims&fy.;
if narcan = 1 then output ssdrive.narcanclaims&fy.;
	else output ssdrive.opioidclaims&fy.;
run;

/*17: 1,253,919; 72
  18: 1,076,791; 813
  19: 882,313; 3,057
  20: 822,296; 4,574
  21: 815,346; 5,948
  22: 758,315; 26,080
  23: 747,256; 26,936
  24: 562,772; 17,106*/

/****************************************************************************************************************************************************
*                                                           Edward's High Dose Identification                                                       *
****************************************************************************************************************************************************/


proc sql;
create table OpiScriptsAPCDwCF_&fy. as 
	/*17:1,253,919; 18:1,076,791; 19:882,313; 20:822,296; 21:815,346; 22:758,315; 23:747,256; 24:562,772*/
  select distinct a.*,
  case
    when MME_Conversion_Factor is null and drug = 'Buprenorphine' and master_form = 'Film' then 30
    when MME_Conversion_Factor is null and drug = 'Buprenorphine' and master_form = 'Patch, Extended Release' then 12.6
    when MME_Conversion_Factor is null and drug = 'Buprenorphine' and master_form = 'Tablet' then 30
    else MME_Conversion_Factor
  end as MME_factor,b.*
  from ssdrive.opioidclaims&fy. a left join lookup.OPIOID_NDC_MME_2020 b
  on PC026_DrugCode = b.ndc;

create table tmp1_&fy. as 
	/*17:1,253,500; 18:1,076,078; 19:881,783; 20:821,807; 21:815,017; 22:757,698; 23:745,973; 24:562,316*/
  select distinct newid,studyid,Member_county,ME173A_MemberCounty,PC001_Submitter,PC026_DrugCode,PC032_DatePrescriptionFilled,PC033_QuantityDispensed,
         PC034_DaysSupply,Strength_Per_Unit,MME_factor,PC107_CarrierSpecificUniqueMembe,quarter
  from OpiScriptsAPCDwCF_&fy.
  where PC034_DaysSupply > 0 and PC033_QuantityDispensed > 0
  order by studyid,PC032_DatePrescriptionFilled,PC026_DrugCode,PC033_QuantityDispensed;

/****** Calculation of MME ******/
*Strength per Unit  X  (Number of Units/ Days Supply) X  MME conversion factor  =  MME/Day;
*Calculate MME per drug and sum for each drug taken on a particular day;

create table OpiScriptsAPCD_MME&fy. as 
	/*17:1,253,500; 18:1,076,078; 19:881,783; 20:821,807; 21:815,017; 22:757,698; 23:745,973; 24:562,316*/
/*keep only distinct ones because that takes care of the MCD-MCD dupes*/
  select distinct newid,Member_county,PC026_DrugCode,PC032_DatePrescriptionFilled,PC033_QuantityDispensed,Strength_Per_Unit,MME_factor,
         PC034_DaysSupply,Strength_Per_Unit*(PC033_QuantityDispensed/PC034_DaysSupply)*MME_factor as MME,quarter,
         case when missing(studyid) then newid
              else studyid
         end as studyid
  from tmp1_&fy. 
  order by studyid,PC032_DatePrescriptionFilled,PC026_DrugCode;
quit;

proc sql;
title "High Dose Counts FY&fy.";
select count(distinct studyid||put(PC032_DatePrescriptionFilled,date9.)) 'MME ge 90' 
	from OpiScriptsAPCD_MME&fy. 
	where mme ge 90;
/*17:94,160; 18:77,825; 19:59,294; 20:65,336; 21:77;724; 22:83,073; 23:89,326; 24:77,191*/
select count(distinct studyid||put(PC032_DatePrescriptionFilled,date9.)) 'MME ge 50' 
	from OpiScriptsAPCD_MME&fy. 
	where mme ge 50;
/*17:236,735; 18:188,567; 19:122,832; 20:116,928; 21:127,021; 22:125,232; 23:126,064, 24:103,706*/

create table prep1_&fy. as 
	/*17:1,253,015; 18:1,075,615; 19:877,369; 20:814,338; 21:808,108; 22:743,309; 23:736,392; 24:552,821*/
  select distinct studyid,Member_county,PC026_DrugCode,PC032_DatePrescriptionFilled,
		PC032_DatePrescriptionFilled as start,PC034_DaysSupply,
         PC032_DatePrescriptionFilled + PC034_DaysSupply-1 as stop format date9.,
		sum(mme) as total_mme
  from OpiScriptsAPCD_MME&fy.
  group by studyid,PC032_DatePrescriptionFilled,PC026_DrugCode;
quit;

/*Calculate MME per day per person and determine whether there was overdose or not by spreading prescription period into days*/
data prep2_&fy.; 
	/*17:21,424,393; 18:18,870,460; 19:14,438,763; 20:13,457,954; 21:13,008,000; 22:12,090,520; 23:11,748,031; 24:8,882,340*/
set prep1_&fy. (keep = studyid Member_county PC032_DatePrescriptionFilled PC034_DaysSupply 
						PC026_DrugCode total_mme start stop 
                rename = (total_mme = mme));
format Day_on_presc date9.;

Day_on_presc = start;
output;
if start lt stop then do;
   do while(stop gt start);
      retain studyid PC026_DrugCode mme PC034_DaysSupply;
      Day_on_presc = start + 1;
      start = start + 1;
      output;
   end;
end;

drop start stop;
run;

/*Sum MME dose for any day on prescription*/
proc sql;
create table OpiScriptsAPCD_DaySum&fy. as 
	/*17:21,424,393; 18:18,870,460; 19:14,438,763; 20:13,457,954; 21:13,008,000; 22:12,090,520; 23:11,748,031; 24:8,882,340*/
  select distinct studyid,PC034_DaysSupply,PC032_DatePrescriptionFilled,Day_on_presc,
		PC026_DrugCode,sum(mme) as MME_total,Member_county,
         case when Calculated MME_total ge 90 then 1
              else 0 
         end as highdose90mme,
         case when Calculated MME_total ge 50 then 1
              else 0 
         end as highdose50mme
  from prep2_&fy.
  group by studyid,Day_on_presc;

create table ssdrive.FinalHDOFlags_&fy. as 
	/*17:356,870; 18:313,202; 19:276,351; 20:251,510; 21:255,491; 22:240,168; 23:241,394; 24:186,029*/
  select studyid,Member_county,max(highdose90mme) as highdose90mme,max(highdose50mme) as highdose50mme
  from OpiScriptsAPCD_DaySum&fy.
  group by studyid,Member_county;

title "Individuals with High Doses FY&fy.";
select count(distinct studyid) as Opi_StudyID format = comma12. 'All Individuals' 
	from ssdrive.FinalHDOFlags_&fy.;
/*17:352,051 18:308,946; 19:272,346; 20:247,665; 21:251,806; 22:237,093; 23:238,510; 24:184,210*/
select count(distinct studyid) as HDO90_StudyID format = comma12. 'MME ge 90' 
	from ssdrive.FinalHDOFlags_&fy. where highdose90mme = 1;
/*17:37,614 18:29,670; 19:18,974; 20:17,769; 21:18,184; 22:17,921; 23:17,220; 24:15,993*/
select count(distinct studyid) as HDO50_StudyID format = comma12. 'MME ge 50' 
	from ssdrive.FinalHDOFlags_&fy. where highdose50mme = 1;
/*17:108,060 18:85,296; 19:53,801; 20:47,258; 21:46,915; 22:43,280; 23:41,373; 24:33,890*/

create table ssdrive.OpioidMemRX_&fy. as 
	/*17:356,870; 18:313,202; 19:276,351; 20:251,510; 21:255,491; 22:240,168; 23:241,394; 24:186,029*/
  select distinct a.studyid,
		b.highdose90mme,b.highdose50mme,
         /*case when missing(a.ME173A_MemberCounty) then 'Missing'
              when a.ME173A_MemberCounty = c.countyfips then c.county_lbl
              when upcase(a.ME173A_MemberCounty) = c.county then c.county_lbl
              else  'Out of State'
         end as county,*/
		a.member_county as county, /*add this because ??*/
         case when not missing(d.studyid) then 1
              else 0
         end as narcan_flag      
  from OpiScriptsAPCD_DaySum&fy. a left join ssdrive.FinalHDOFlags_&fy. b on a.studyid = b.studyid
  																				and a.member_county=b.member_county
                                   left join ssdrive.narcanclaims&fy. d on a.studyid = d.studyid
  																				and a.member_county=d.member_county
                                  /* left join geo.Ar_regions_co_xwalk c on a.member_county = c.countyfips or
                                                                              upcase(a.ME173A_MemberCounty) = c.county*/;

title "High Dose Narcan Counts FY&fy.";
select count(distinct studyid) as HDOwNarcan90 
	from ssdrive.OpioidMemRX_&fy. 
	where narcan_flag = 1 and highdose90mme = 1;
/*17:51; 18:533; 19:1,134; 20:1,441; 21:1,995; 22:5,212; 23:4,117; 24:2,684*/
select count(distinct studyid) as HDOwNarcan50 
	from ssdrive.OpioidMemRX_&fy. 
	where narcan_flag = 1 and highdose50mme = 1;
/*17:62; 18:632; 19:1,745; 20:2,311; 21:2,951; 22:9,018; 23:7,744; 24:4,780*/

create table ssdrive.OpioidbyCountycnts_&fy. as /*76 (missing  + 75 counties)*/
  select county,count(distinct studyid) as members_w_opi format= comma12.,sum(highdose90mme) as members_w_90mme format = comma12.,sum(highdose50mme) as members_w_50mme
         format = comma12.,sum(narcan_flag) as members_w_narcan format= comma12.
  from ssdrive.OpioidMemRX_&fy.
  group by county
  order by county;
quit;
title;

proc sql; 
/*(duplicate counties/lived in two? I think we are okay with this but jic we aren't...) */
/*17:9,520; 18:8,424; 19:7,938; 20:7,609; 21:7,307; 22:6,100; 23:5,709; 24:3,610*/
create table checkingdups as
select distinct *
	from ssdrive.OpioidMemRX_&fy.
	group by studyid
		having count(*)>1;
quit;

/***************************************************************************************************************/
/*BY QUARTER*/
/*FOR THE MOST RECENT YEAR ONLY*/
proc sql;
create table prep1_&fy.Q as /*24:552,821*/
  select distinct studyid,PC026_DrugCode,PC032_DatePrescriptionFilled,
		PC032_DatePrescriptionFilled as start,PC034_DaysSupply,
        PC032_DatePrescriptionFilled + PC034_DaysSupply - 1 as stop format date9.,
		sum(mme) as total_mme,member_county,quarter
	from OpiScriptsAPCD_MME&fy.
	group by studyid,PC032_DatePrescriptionFilled,PC026_DrugCode;
quit;

/*Calculate MME per day per person and determine whether there was overdose or not by spreading prescription period into days*/
data prep2_&fy.Q;  /*24:8,882,340*/
set prep1_&fy.Q (keep = studyid PC032_DatePrescriptionFilled PC034_DaysSupply 
					PC026_DrugCode total_mme start stop quarter member_county
                 	rename = (total_mme = mme));
format Day_on_presc date9.;

Day_on_presc = start;
output;
if start lt stop then do;
   do while(stop gt start);
      retain studyid mme PC034_DaysSupply;
      Day_on_presc = start + 1;
      start = start + 1;
      output;
   end;
end;

drop start stop;
run;

proc sql;
/*Sum MME dose for any day on prescription*/
create table OpiScriptsAPCD_DaySum&fy.Q as /*24:8,882,340*/
  select distinct studyid,quarter,member_county,PC034_DaysSupply,
		PC032_DatePrescriptionFilled,Day_on_presc,
		PC026_DrugCode,sum(mme) as MME_total,
         case when Calculated MME_total ge 90 then 1
              else 0 
         end as highdose90mme,
         case when Calculated MME_total ge 50 then 1
              else 0 
         end as highdose50mme
  from prep2_&fy.Q
  group by studyid,Day_on_presc;

create table ssdrive.FinalHDOFlags_&fy.Q as /*24:281,162*/
  select studyid,quarter,member_county,
		max(highdose90mme) as highdose90mme,max(highdose50mme) as highdose50mme
  from OpiScriptsAPCD_DaySum&fy.Q
  group by studyid,quarter,member_county;

title "Individuals with High Doses FY&fy.Q";
select quarter,count(distinct studyid) as Opi_StudyID format = comma12. 'All Individuals' 
	from ssdrive.FinalHDOFlags_&fy.Q
	group by quarter;
/*FY2023Q1 82,963 
  FY2023Q2 78,316 
  FY2023Q3 58,936 
  FY2023Q4 60,034 */
select quarter,count(distinct studyid) as HDO90_StudyID format = comma12. 'MME ge 90' 
	from ssdrive.FinalHDOFlags_&fy.Q 
	where highdose90mme = 1
	group by quarter;
/*FY2023Q1 9,630 
  FY2023Q2 9,850 
  FY2023Q3 7,418 
  FY2023Q4 7,085 */
select quarter,count(distinct studyid) as HDO50_StudyID format = comma12. 'MME ge 50' 
	from ssdrive.FinalHDOFlags_&fy.Q 
	where highdose50mme = 1
	group by quarter;
/*FY2023Q1 17,768 
  FY2023Q2 18,105 
  FY2023Q3 13,748 
  FY2023Q4 13,037 */
title;
create table ssdrive.OpioidMemRX_&fy.Q as /*24:281,162*/
  select distinct a.studyid,a.quarter,a.member_county,
		b.highdose90mme,
		b.highdose50mme,
         case when not missing(c.studyid) then 1
              else 0
         end as narcan_flag      
  from OpiScriptsAPCD_DaySum&fy.Q a 
		left join ssdrive.FinalHDOFlags_&fy.Q b 
			on a.studyid = b.studyid
				and a.quarter=b.quarter
				and a.member_county=b.member_county
        left join ssdrive.narcanclaims&fy. c
			on a.studyid = c.studyid
				and a.quarter=c.quarter
				and a.member_county=c.member_county;
			  /* LINKING BY QUARTER DROPS SOME PRESCIPTION LINKS; DROPPING THIS
			     SECTION FOR QUARTERLY - MM*/

title "Individuals with High Dose Narcan FY&fy.Q";
select quarter,count(distinct studyid) '90 MME w Narcan' 
	from ssdrive.OpioidMemRX_&fy.Q 
	where narcan_flag = 1 and highdose90mme = 1
	group by quarter;
/*FY2023Q1 717 
  FY2023Q2 696 
  FY2023Q3 613 
  FY2023Q4 487 */
select quarter,count(distinct studyid) '50 MME w Narcan' 
	from ssdrive.OpioidMemRX_&fy.Q 
	where narcan_flag = 1 and highdose50mme = 1
	group by quarter;
/*FY2023Q1 1230 
  FY2023Q2 1205 
  FY2023Q3 1055 
  FY2023Q4 863 */
quit;
title;

