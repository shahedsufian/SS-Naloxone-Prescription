/****************************************************************************************************************************************************
*                                                                                                                                                   *
* PURPOSE: To investigate the co-prescribing Naloxone/Narcan and high dose opioid prescriptions.                                                    *
*                                                                                                                                                   *
* Date: 17 Jun 2025                                                                                                                               *
*                                                                                                                                                   *
*    v0.1 																																		      *
*                                                                                                                                                   *
* PROJECT: Opioid Studies                                                                                                                           *
*                                                                                                                                                   *
****************************************************************************************************************************************************/
options compress=yes;
options symbolgen;
option mprint mlogic;

libname ssdrive '';

libname rdrive '';

/****** APCD and APCD Reference Tables ******/
libname apcd '';

libname mcr ''; /*SS-C; The mcr library has not been used in the subsequent files. Most 
										likely Medicare datasets don't need to be used.*/

libname apcdlu ODBC noprompt = "" schema = lookups;

/****** NCD Code list CDC sent an updated file June 2020 ******/
libname lookup "";
libname geo '';

libname mstrprov ODBC NOPROMPT="" SCHEMA=dbo; /*master provider solution */

/****** Macro Variables to be used below ******/
%let st_yr=16; /*??*/
%let en_yr=24;
%let apcdvers = 24c;
/*%let mme = lookup.OPIOID_NDC_MME_2020;*/
/*%let apcd_bene = apcd.apcd_member24c;*/

/*%let bene= ssdrive.All_MCR_APCD_Mems;*/

%let ds = ssdrive.NarcanEligible;
%let start_1 = "01JUL20&st_yr."d;
%let stop_1 = "30JUN20&en_yr."d;
%let nwa_counties = "WASHINGTON","BENTON","CARROLL","MADISON";
/*change below when re-running to change name of excel output*/
%let xlvers = v0.1 20250617;

/*%let varis = ME001_Submitter,ME107_CarrierSpecificUniqueMembe,newid,ME003_InsuranceType_ProductCode,ME998_APCDUniqueId,ME013_MemberGender,*/
/*             ME014_MemberDateOfBirth,studyid,ME162A_DateOfFirstEnrollment,ME163A_DateOfDisenrollment,type_of_cov;*/
/**/
/*			 */
/*%let varis = 	ME001_Submitter,ME107_CarrierSpecificUniqueMembe,newid,ME003_InsuranceType_ProductCode*/
/*				,ME998_APCDUniqueId,ME013_MemberGender,ME014_MemberDateOfBirth,studyid*/
/*				,ME173A_MemberCounty,ME162A_DateOfFirstEnrollment,ME163A_DateOfDisenrollment,type_of_cov;*/

%let keep_var = 	PC001_Submitter PC003_InsuranceType_ProductCode PC004_PayerClaimControlNumber PC005_LineNumber PC012_MemberGender
                    PC013_MemberDateOfBirth PC015_MemberStateOrProvince PC016_MemberZipCode PC020_PharmacyName PC021_NationalProviderIDNumber_S
                    PC026_DrugCode PC027_DrugName PC028_FillNumber PC032_DatePrescriptionFilled PC033_QuantityDispensed PC034_DaysSupply
                    PC035_ChargeAmount PC036_PaidAmount PC037_IngredientCost_ListPrice PC039_DispensingFee PC040_CopayAmount PC041_CoinsuranceAmount
                    PC042_DeductibleAmount PC043_PrescribingProviderId PC044_PrescribingPhysicianFirstN PC046_PrescribingPhysicianLastNa
                    PC048_NationalProviderID_Prescri PC058_ScriptNumber PC107_CarrierSpecificUniqueMembe PC006_InsuredGroupNumberOrPolicy;

%let keep_vars_sql = PC001_Submitter, PC003_InsuranceType_ProductCode, PC004_PayerClaimControlNumber, PC005_LineNumber, PC012_MemberGender,
                    PC013_MemberDateOfBirth, PC015_MemberStateOrProvince, PC016_MemberZipCode, PC020_PharmacyName, PC021_NationalProviderIDNumber_S,
                    PC026_DrugCode, PC027_DrugName, PC028_FillNumber, PC032_DatePrescriptionFilled, PC033_QuantityDispensed, PC034_DaysSupply,
                    PC035_ChargeAmount, PC036_PaidAmount, PC037_IngredientCost_ListPrice, PC039_DispensingFee, PC040_CopayAmount, PC041_CoinsuranceAmount,
                    PC042_DeductibleAmount, PC043_PrescribingProviderId, PC044_PrescribingPhysicianFirstN, PC046_PrescribingPhysicianLastNa,
                    PC048_NationalProviderID_Prescri, PC058_ScriptNumber, PC107_CarrierSpecificUniqueMembe, PC006_InsuredGroupNumberOrPolicy;

%let vari = case 
				when missing(studyid) then newid 
				else studyid 
			end as studyid
			,member_county
			,newid
			,year,PC001_Submitter,PC004_PayerClaimControlNumber
			,PC012_MemberGender,PC013_MemberDateOfBirth
			,PC026_DrugCode,PC027_DrugName,PC032_DatePrescriptionFilled,PC033_QuantityDispensed
			,PC034_DaysSupply,PC036_PaidAmount,PC037_IngredientCost_ListPrice,PC039_DispensingFee
			,PC040_CopayAmount,PC041_CoinsuranceAmount,PC042_DeductibleAmount,PC043_PrescribingProviderId
			,PC044_PrescribingPhysicianFirstN,PC046_PrescribingPhysicianLastNa,PC048_NationalProviderID_Prescri
			,PC058_ScriptNumber;

%let mem_varis = compress(ME001_Submitter||ME107_CarrierSpecificUniqueMembe) as newid,ME001_Submitter,ME107_CarrierSpecificUniqueMembe,
                 compress(ME998_APCDUniqueId||ME013_MemberGender||put(ME014_MemberDateOfBirth,date9.)) as studyid,ME998_APCDUniqueId,
                 ME014_MemberDateOfBirth,ME013_MemberGender,ME016_MemberStateOrProvince,ME017_MemberZipCode,ME173A_MemberCounty,
                 ME003_InsuranceType_ProductCode,ME007_CoverageLevelCode,ME164A_HealthPlan,ME018_MedicalServicesIndicator,
                 ME019_PharmacyServicesIndicator,ME020_DentalServicesIndicator,ME018A_Medical_Claim_Match_Flag,ME019A_Pharmacy_Claim_Match_Flag,
                 ME020A_Dental_Claim_Match_Flag,ME030_MarketCategory,ME040_ProductIdentifier,ME056_LastActivityDate,ME057_DateOfDeath,
                 ME059_DisabilityIndicator,ME063_BenefitStatus,ME120_ActuarialValue,ME121_MetallicValue,ME123_MonthlyPremium,
                 ME124_Attributed_PCP_ProviderId,ME032_GroupName,ME162A_DateOfFirstEnrollment,ME163A_DateOfDisenrollment,ME992_HIOS_ID,
                 PeriodBeginDate,PeriodEndingDate,ME006_InsuredGroupOrPolicyNumber;



/*Do this first*/

/*NDCs*/
/*this part only run the first time!
	NDC list from 2022*/
libname R_on2022 "";
	data ssdrive.NarcanNDC_list;
	set R_on2022.NarcanNDC_list; /*SS-Q: Do I need to use an updated table here? No*/
run;
libname R_on2022 clear;

proc sql;
/*opioid ndc*/
create table opioid_ndc_info as
select distinct ndc
	from lookup.OPIOID_NDC_MME_2020 /*SS-Q: Do I need to use an updated table here? No*/
	where Class = 'Opioid'; 

/*Narcan ndc*/
select distinct quote(substr(ndc_code,1,9)) into: narcan_ndc_list separated by ","
	from ssdrive.NarcanNDC_list; /*69 - Narcan list from 2022 run*/
quit;



 