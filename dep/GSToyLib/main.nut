/* -*- Mode: C++; tab-width: 6 -*- */
/*
 *
 * This file is part of GSToyLib a library for OpenTTD noai and nogo
 * Copyright (C) 2014 Krinn <krinn@chez.com>
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

require("version.nut");
class GSToyLib {
    static State = { scp_handle = null, alone = true, give_money = true, info_output = false }; /**< scp_handle store the script given handle for scp or the one we use if none was given, alone is set to true when the script didn't gave us its scp_handle (so null), give_money enable/disable the lib to give money to AIs, info_output enable/disable outputing of message from the lib itself */
    static CompanyMoneyList = GSList(); /**< List of companies that have ask us money */
    static CompanyExemptionList = GSList(); /**< List of companies that have ask us exemption */

    constructor(scp_handle, gs_instance) {
        if (scp_handle == null) {
            /**<  We will handle SCP ourselves if the main script don't use scp */
            scp_handle = SCPLib(GSTOYLIB_SHORTNAME, GSTOYLIB_VERSION, null);
            GSToyLib.State.alone = true;
        } else {
            GSToyLib.State.alone = false;
        }
        GSToyLib.State.scp_handle = scp_handle;
        for (local i=0; i < 15; i++) { 
            GSToyLib.CompanyMoneyList.AddItem(i, 0);
            GSToyLib.CompanyExemptionList.AddItem(i, 0);
        }
        scp_handle.SetEventHandling(true); /**< force events on, we don't know if the script that host us handle them or not.*/
        scp_handle.SCPLogging_Error(true);
        scp_handle.AddCommand("MoneyPlease", "GSToyLib Set v" + GSTOYLIB_VERSION, this, GSToyLib.ToyAskMoney);
        scp_handle.AddCommand("Exemption", "GSToyLib Set v" + GSTOYLIB_VERSION, this, GSToyLib.AskExemption);
        GSToyLib.State.info_output = false;
        GSToyLib.State.give_money = true;
    }
}

function GSToyLib::SCPConfigChange(events, info, error)
/**
 * Change some SCP configuration, this is to allow a script not using SCP still be able to alter some basic SCP configuration
 * Default are : events true, info and error to false
 * @param events true to enable SCP to handle events for the host script (if your script don't use events, enable it)
 * @param info true to enable SCP debug message (it will flood you)
 * @param error true to enable SCP reporting errors messages (that's still an SCP debug feature), but reporting errors from SCP can help users see your script isn't at fault
 */
{
    GSToyLib.State.scp_handle.SetEventHandling(events);
    GSToyLib.State.scp_handle.SCPLogging_Error(error);
    GSToyLib.State.scp_handle.SCPLogging_Info(info);
}

function GSToyLib::Check()
/**
 * Check do nothing more than just called the SCPLib.Check, while we must have that check done, script using SCP are already doing it, so they just don't need that function
 * If the lib was init with an SCP handle, this will do nothing, leaving the SCP Check done by the hosting script. Unlike SCPLIb.Check this function handle all events in one time and return nothing ; for a more fine tuning Check use the SCPLib.Check function.
 */
{
    if (GSToyLib.State.alone)    while (GSToyLib.State.scp_handle.Check()) {};
}

function GSToyLib::MoneyHandling(allow_money)
/**
 * Change if the lib allow AIs to get money, using that function you can add a parameter in your host script to disallow/allow it to gives money or not
 * @param allow_money true to gives money to who ask some, false to stop that
 */
{
    GSToyLib.State.give_money = allow_money;
}

function GSToyLib::LibPrintMessage(allow_print)
/**
 * Change if the lib is allow to use GSInfo.Log or GSInfo.Warning output to the console, this is mostly informative or for debug. Could be a nice feature to add as option, many admin will love to see to who the lib actually gives money in their logs.
 * @param allow_print true to enable the lib outputing to the console, false to keep the lib quiet.
 */
{
    GSToyLib.State.info_output = allow_print;
}

function GSToyLib::LogStats()
/**
 * Output to console the amount of money all companies had from us. Beware of integer overflow if the AI ask us a lot or if it has run a long time. Because this function is only to output to console, the function don't care about the LibPrintMessage setting (it will always output)
 */
{
    GSLog.Info("GSToyLib> Companies status: ");
    foreach (comp, value in GSToyLib.CompanyMoneyList) {
        if (GSCompany.ResolveCompanyID(comp) == GSCompany.COMPANY_INVALID)    { continue; }
        local company = GSCompany.GetName(comp)+" (#"+comp+")";
        GSLog.Info("GSToyLib> Company: "+company+" amount: "+value);
    }
    foreach (comp, value in GSToyLib.CompanyExemptionList) {
        if (GSCompany.ResolveCompanyID(comp) == GSCompany.COMPANY_INVALID)    { continue; }
        local company = GSCompany.GetName(comp)+" (#"+comp+")";
        GSLog.Info("GSToyLib> Company: "+company+" status: "+value);
    }
}

function GSToyLib::IsToyAI(companyID)
/**
 * Test if a company has taken our money and if the GS can consider it a toy/eyes candy... AI. It just answer if the company had money from us, if the company didn't ask us money yet, it might still be a ToyAI. If the company collapse and another AI run it now, it will answer true as we don't track company changes (this shouldn't be a big issue, if we gave it money, it shouldn't collapse)
  * @param companyID the id of the company you want test.
  * @return true if the company got money from us at least one time.
 */
{
    return (GSToyLib.CompanyMoneyList.GetValue(companyID) != 0);
}

function GSToyLib::IsExemptedAI(companyID)
/**
 * Test if a company has requested exemption. This allows the GS to identify AI companies
 * that have been exempted from certain game rules without receiving money.
 * @param companyID the id of the company you want test.
 * @return true if the company has requested exemption at least one time.
 */
{
    return (GSToyLib.CompanyExemptionList.GetValue(companyID) != 0);
}

function GSToyLib::IsAI(companyID)
/**
 * Test if a company has been treated as an AI by this library, either by receiving
 * money or by requesting exemption. This is a combined check of IsToyAI and IsExemptedAI.
 * @param companyID the id of the company you want test.
 * @return true if the company got money from us OR has requested exemption.
 */
{
    return (GSToyLib.CompanyMoneyList.GetValue(companyID) != 0 || GSToyLib.CompanyExemptionList.GetValue(companyID) != 0);
}

function GSToyLib::ToyAskMoney(message, self)
/**
 * That's how the lib handle money query, nothing more than a "classic" SCP typeof message (see http://wiki.openttd.org/SCPLib_doc#Message if your are curious)
 * @param message an SCP message type get from an SCP host querying you
 * @param self the "this" context pass with the message, not need in our lib
 */
{
    if (GSCompany.ResolveCompanyID(message.SenderID) == GSCompany.COMPANY_INVALID) {
        GSLog.Warning("GSToyLib> Company #"+message.SenderID+" is not valid anymore");
        return;
    }
    local company = GSCompany.GetName(message.SenderID)+" (#"+message.SenderID+")";
    if (typeof(message.Data[0]) != "integer") {
        if (GSToyLib.State.info_output)    GSLog.Warning("GSToyLib> Client "+company+" ask us non integer amount of money : "+message.Data[0]);
        return;
    }
    if (GSToyLib.State.give_money != true) {
        if (GSToyLib.State.info_output)    GSLog.Info("GSToyLib> No amount given as gamescript parameter reject request for money now.");
        return;
    }
    GSCompany.ChangeBankBalance(message.SenderID, message.Data[0], GSCompany.EXPENSES_OTHER, GSMap.TILE_INVALID);
    if (GSToyLib.State.info_output) {
        GSLog.Info("GSToyLib> Giving "+message.Data[0]+" to company "+company);
    }
    local value = GSToyLib.CompanyMoneyList.GetValue(message.SenderID);
    value += message.Data[0];
    GSToyLib.CompanyMoneyList.SetValue(message.SenderID, value);
}

function GSToyLib::AskExemption(message, self) {
    if (GSCompany.ResolveCompanyID(message.SenderID) == GSCompany.COMPANY_INVALID) {
        GSLog.Warning("GSToyLib> Company #"+message.SenderID+" is not valid anymore");
        return;
    }
    local company = GSCompany.GetName(message.SenderID)+" (#"+message.SenderID+")";
    if (GSToyLib.State.info_output) {
        GSLog.Info("GSToyLib> Company " + company + "Receiving Exemption Request: " + message.Data[0]);
    }
    // Record that this company requested exemption
    GSToyLib.CompanyExemptionList.SetValue(message.SenderID, 1);
    GSToyLib.State.scp_handle.Answer(message, 0);
}