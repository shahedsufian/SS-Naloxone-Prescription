/****************************************************************************************************************************************************
*  PURPOSE: Provide percentge of state prescriptions of Narcan as well as the ability to look at prescribers.                                       *
*                                                                                                                                                   *
*  Date: 25 Jun, 2025                                                                                                                              *
*                                                                                                                                                   *
*  v1.0                                                                                                                                             *
*                                                                                                                                                   *
*  PROJECT: Opioid Studies                                                                                                                          *
*                                                                                                                                                   *
****************************************************************************************************************************************************/

/* Combining the tables from the Narcan (Step 1) Program*/
%macro base_narcan(start,stop); /*84,586*/
proc sql;
create table ssdrive.narcan_prov_info as 
  select &vari. from ssdrive.narcanclaims&start. 
%do yr = %eval(&start. + 1) %to &stop.;
outer union corresponding
  select &vari from ssdrive.narcanclaims&yr.
%end;;
quit;
%mend;
%base_narcan(17,24);

/* Checking counts for overall Providers and those with missing last names */
proc sql;
select count(distinct compress(PC001_Submitter||PC043_PrescribingProviderId)) 
	from ssdrive.narcan_prov_info; /*13,861*/

select count(distinct compress(PC001_Submitter||PC043_PrescribingProviderId)) 
	from ssdrive.narcan_prov_info  /*36*/
  where missing(PC048_NationalProviderID_Prescri);

select count(distinct PC048_NationalProviderID_Prescri) 
	from ssdrive.narcan_prov_info; /*5,333*/

select count(distinct PC048_NationalProviderID_Prescri) 
	from ssdrive.narcan_prov_info  /*459*/
  where missing(PC043_PrescribingProviderId);

select distinct PC043_PrescribingProviderId 
	from ssdrive.narcan_prov_info 
	where missing(PC048_NationalProviderID_Prescri) 
	group by PC001_Submitter;
quit;

/* Grabbing provider npi */
proc sql;
create table ssdrive.Prescribers_NPI as /*5,359*/
  select distinct case 
					when missing(PC048_NationalProviderID_Prescri) 
						then PC043_PrescribingProviderID
					else PC048_NationalProviderID_Prescri
                  end as NPI
from ssdrive.narcan_prov_info
where not missing(calculated NPI);
quit;

/*Use provider NPI to extract provider information*/
data ssdrive.Prescribers_NPI_Info; /*5,055*/
if _n_= 1 then 
	do;
		if 0 then set ssdrive.Prescribers_NPI;
		declare hash npi_info(dataset: "ssdrive.Prescribers_NPI");
		npi_info.definekey("NPI");
		npi_info.definedone();
	end;

set lookup.NPI_DATABASE_V02_2022;

rc= npi_info.find();

if rc= 0 then 
	do;
		if missing(Provider_Middle_Name) then Prescriber_name = trim(Provider_First_Name)||' '||trim(Provider_Last_Name_Legal_Name);
		else Prescriber_name = trim(Provider_First_Name)||' '||trim(Provider_Middle_Name)||' '||trim(Provider_Last_Name_Legal_Name);
		keep NPI Prescriber_name;
		output;
	end;
run;

/*Join provider information with Pharm claims and process further*/
data ssdrive.prescribing_prov_names ; /*84,586*/
length Provider_Type $10;
if _n_= 1 then 
	do;
		if 0 then set ssdrive.Prescribers_NPI_Info;
		declare hash npi_finder(dataset: "ssdrive.Prescribers_NPI_Info");
		npi_finder.definekey("NPI");
		npi_finder.definedata(all:"yes");
		npi_finder.definedone();
	end;

set ssdrive.narcan_prov_info;

rc= npi_finder.find(key:PC048_NationalProviderID_Prescri);

if rc ne 0 then call missing(NPI,Prescriber_name);
Prescribing_Provider = coalescec(Prescriber_name,trim(PC044_PrescribingPhysicianFirstN)||
									' '||trim(PC046_PrescribingPhysicianLastNa));

if Prescribing_Provider in ("APPATHURAI BALAMURUGAN","NATHANIEL H SMITH","JENNIFER ALLYN DILLAHA"
							,"JOSE R ROMERO","RENEE MALLORY" ) then Provider_Type="State";
/*check if this is actually used; we need to check these names for this year?
	change year over year?*/
else if not missing(Prescribing_Provider) then Provider_Type="Other";
else Provider_Type = "Missing";
run;

proc sql;
create table missinginfo as /*12*/
select distinct npi, count(*) as scriptcount
	from ssdrive.prescribing_prov_names
	where npi is not missing and Prescriber_name is missing
	group by npi;
quit;
/*SS-Q: How to do the following check? I checked by hand and only two of these providers (each with one script) were on the NPI website. 
The rest had been deactivated*/

/*list of providers in most recent FY */
proc sql;
create table Prescribers_in_FY20&en_yr. as /*2,448*/
select distinct Prescribing_Provider, count(distinct compress(studyid||(put(PC032_DatePrescriptionFilled,date9.)))) as numrxs
from ssdrive.prescribing_prov_names
where year= "FY20&en_yr."
group by Prescribing_Provider
/*order by Prescribing_Provider*/
order by numrxs desc
;
quit;

/********************************************Pharmacists****************************************************/

proc sql;
create table Rx_npi_1 as
select distinct npi,Prescriber_name
from ssdrive.prescribing_prov_names
where not missing(npi)
;
select count(distinct npi) from Rx_npi_1; /*5,055*/
quit;


proc sql;
create table npi_info as /* 5,055 */
select distinct npi, 
	Healthcare_Prov_Taxonomy_Code_1,
	Healthcare_Prov_Taxonomy_Code_2,
	Healthcare_Prov_Taxonomy_Code_3,
	Healthcare_Prov_Taxonomy_Code_4,
	Healthcare_Prov_Taxonomy_Code_5,
	Healthcare_Prov_Taxonomy_Code_6,
	Healthcare_Prov_Taxonomy_Code_7,
	Healthcare_Prov_Taxonomy_Code_8
from lookup.npi_database_v02_2022
where npi in (select npi from Rx_npi_1)
;
select count(distinct npi) from npi_info; /*5,055*/;
quit;

proc sql;
create table npi_to_taxodesc_careprec as /* 7,052 */
select distinct *,
				case 
					when upcase(TaxoDescr) contains "PHARM" then 1
					else 0
				end as pharmacist
from mstrprov.Prov_Taxonomy_2021
where npi in (select npi from Rx_npi_1)
;
select count(distinct npi) from npi_to_taxodesc_careprec; /*5,027 */
quit;


proc sql;
select distinct TaxoDescr 
	from npi_to_taxodesc_careprec 
	where upcase(TaxoDescr) contains "PHARM"; 

select distinct TaxoDescr,taxo 
	from npi_to_taxodesc_careprec 
	where upcase(TaxoDescr) contains "PHARM"; 

select distinct quote(trim(taxo)) into :pharm_taxo separated by ","
	from npi_to_taxodesc_careprec 
	where upcase(TaxoDescr) contains "PHARM"; 

select distinct npi,count(distinct npi) 
	from /*selecting npi which we do not have information form*/
			(select distinct npi from Rx_npi_1 
				except 
			select distinct npi from npi_to_taxodesc_careprec);
quit;

proc sql;
create table npi_not_in_careprec as /*28 */
select distinct a.npi,
				case
					when b.Healthcare_Prov_Taxonomy_Code_1 in (&pharm_taxo.)
						or b.Healthcare_Prov_Taxonomy_Code_2 in (&pharm_taxo.)
						or b.Healthcare_Prov_Taxonomy_Code_3 in (&pharm_taxo.)
						or b.Healthcare_Prov_Taxonomy_Code_4 in (&pharm_taxo.)
						or b.Healthcare_Prov_Taxonomy_Code_5 in (&pharm_taxo.)
						or b.Healthcare_Prov_Taxonomy_Code_6 in (&pharm_taxo.)
						or b.Healthcare_Prov_Taxonomy_Code_7 in (&pharm_taxo.)
						or b.Healthcare_Prov_Taxonomy_Code_8 in (&pharm_taxo.) then 1
					else 0
				end as pharmacist,
				b.*
			
from 
	(select distinct npi from Rx_npi_1 
	except 
	select distinct npi from npi_to_taxodesc_careprec) a
		inner join npi_info b on a.npi = b.npi
;
quit;

/*identifying all pharmacists using NPI*/
proc sql;
create table ssdrive.Rx_Prescriber_details as /*5,055*/
select distinct npi,
				Prescriber_name,
				case
					when npi in (select npi from npi_to_taxodesc_careprec where pharmacist=1
									union select npi from npi_not_in_careprec where pharmacist= 1)
						then 1
					else 0
				end as pharmacist,
				case
					when npi in ("1487970521","1649240912","1174722904") then "State"
/*NPIs correspond to names used ("APPATHURAI BALAMURUGAN","NATHANIEL H SMITH","JENNIFER ALLYN DILLAHA")*/
					when calculated pharmacist= 1 then "Pharmacist"
					else "Other Provider"
				end as Provider_Type

	from Rx_npi_1
;
select count(distinct npi) from ssdrive.Rx_Prescriber_details; /*5,055*/
quit;

/*updating provider info on analytic table*/
proc sql; /*84,586*/
create table prescribing_prov_names as
select distinct coalescec(b.Provider_Type,"Other Provider") as Provider_Type_1,
				c.member_county,
				a.*			

from ssdrive.prescribing_prov_names a
left join ssdrive.Rx_Prescriber_details b on a.npi= b.npi
left join ssdrive.narcan_prov_info c 
	on a.studyid= c.studyid and a.PC004_PayerClaimControlNumber= c.PC004_PayerClaimControlNumber
;
quit;

data ssdrive.prescribing_prov_names; /*84,586*/
set prescribing_prov_names;
run;

/*statewide*/
proc sql;
/* Creates counts for prescriptions by each Provider type */
create table prov_rx_cnts as /*22*/
  select distinct a.year,a.Provider_Type_1,
		count(distinct compress(studyid||PC026_DrugCode||
        		 put(PC032_DatePrescriptionFilled,date9.))) as numrxs format=comma9.,
		 calculated numrxs/b.numrxs as Rx_pct_in_SFY format=percent9.1
  from  ssdrive.prescribing_prov_names a
  left join (select distinct year,count(distinct compress(studyid||PC026_DrugCode||put(PC032_DatePrescriptionFilled,date9.))) as numrxs
  				from  ssdrive.prescribing_prov_names group by year) b 
	on a.year = b.year

  group by a.year,a.Provider_Type_1
  order by a.year,a.Provider_Type_1
;
quit;

/*NWA only*/

proc sql;
/* Creates counts for prescriptions by each Provider type */
create table prov_rx_cnts_nwa as /*18*/
  select distinct a.year,a.Provider_Type_1,count(distinct compress(studyid||PC026_DrugCode||
         put(PC032_DatePrescriptionFilled,date9.))) as numrxs format=comma9.,
		 calculated numrxs/b.numrxs as Rx_pct_in_SFY format=percent9.1
  from  ssdrive.prescribing_prov_names a
  left join (select distinct year,count(distinct compress(studyid||PC026_DrugCode||put(PC032_DatePrescriptionFilled,date9.))) as numrxs
  				from ssdrive.prescribing_prov_names 
				where member_county in (&nwa_counties.) group by year) b 
	on a.year = b.year
where member_county in (&nwa_counties.)

  group by a.year,a.Provider_Type_1
  order by a.year,a.Provider_Type_1
;
quit;



