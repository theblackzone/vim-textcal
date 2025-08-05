" =============================================================================
" File.........: textcal.vim
" Purpose......: VIM plugin to create a simple calender for a given year
" Author.......: TheBlackzone <theblackzone@gmail.com>
" Created......: 2023-12-29
" Last Change..: 2025-08-05
" -----------------------------------------------------------------------------
" textcal.vim is a Vim plugin that generates a year-long plain-text calendar
" inside a new buffer. It includes public holidays (for Germany), calculates
" Easter using Butcher’s algorithm, and highlights potential bridge days
" between holidays and weekends.
"
" Once the plugin is loaded, use the command:
"
" :TextCal <optional year>
"
" to create a calendar for the specified year, or for the current year if no
" year is given.
"
" Please note:
" The output format is tailored to meet the specific needs of my own
" organizational workflow. The generated calendar includes a Vim modeline with
" custom settings - in particular, a reference to the 'rs_outliner.vim' syntax
" file, which is used to colorize the calendar. This syntax file is not
" included with the plugin.
"
" All in all, the default setup may not suit your requirements out of the box, 
" but feel free to customize it to fit your own needs. :-)
"
" This plugin is based on a Perl script ('textcal.pl') I originally wrote on
" Nov 15, 2005. It was later replaced by a Python version ('textcal.py') with
" minor improvements on Feb 4, 2012. The current Vim script version was
" developed between 2023-12-19 17:23 and 2023-12-28 17:21 to remove external
" dependencies entirely.
" =============================================================================

" Exit if the plugin is already loaded or 'compatible' option is set
if exists("loaded_textcal_plugin") || &cp
	finish
endif
let loaded_textcal_plugin = 1

" We are using line continuations
let s:cpo_sav = &cpo
set cpo&vim

set encoding=utf-8

command! -nargs=? TextCal		call textcal#RunTextCal(<f-args>)


"-------------------------------------------------------------------------------
" Easter() - Calculate the Easter date with Butcher's Algorithm
" Takes an integer 'year' as input to calculate the Easter date for that year.
" Returns an array with the calculated Easter date in the form [year,month,day]
"
" The algorithm is taken from:
" https://de.wikibooks.org/wiki/Astronomische_Berechnungen_f%C3%BCr_Amateure/_Kalender/_Berechnungen
"-------------------------------------------------------------------------------

function! s:Easter(year)
	let a = fmod(a:year,19)
	let b = floor(a:year/100)
	let c = fmod(a:year,100)
	let d = floor(b/4)
	let e = fmod(b,4)
	let f = floor((b+8)/25)
	let g = floor((b-f+1)/3)
	let h = fmod((19 * a + b - d - g + 15),30)
	let i = floor(c/4)
	let k = fmod(c,4)
	let m = fmod((32 + 2 * e + 2 * i - h -k),7)
	let n = floor((a + 11 * h + 22 * m)/451)
	let p = floor((h + m - 7 * n + 114)/31)
	let q = fmod((h + m - 7 * n + 114),31)
	let month = float2nr(p)
	let day = float2nr(q+1)
	return [a:year,month,day]
endfunction


"-------------------------------------------------------------------------------
" Leapyear() - Check if a given year is a leap year
" Takes an integer 'year' as input and returns '1' if the year is a leap year
" or '0' if it isn't
"-------------------------------------------------------------------------------
"
function! s:Leapyear(year)
	if fmod(a:year,4) != 0
	   	return(0)
	endif
	if fmod(a:year,100) != 0 
		return(1)
	endif
	if fmod(a:year,400) != 0
		return(0)
	endif
	return(1)
endfunction


"-------------------------------------------------------------------------------
" DayOfYear() - Calculates the number of days since the beginning of a year
" Takes three integers for 'year', 'month' and 'day' as input and returns 
" the number of days since January, 1st.
"-------------------------------------------------------------------------------

function! s:DayOfYear(year,month,day)
	let dim = [31, 28+s:Leapyear(a:year), 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	let doy = 0
	let i=0
	while i<a:month-1
		let doy = doy + dim[i]
		let i+=1
	endwhile
	let doy = doy + a:day
	return doy
endfunction


"-------------------------------------------------------------------------------
" DateFromDOY() - Calculates the date for a given 'DayOfYear'
" Takes 'year' and the 'doy' (DayOfYear, Days since January 1st) as input and 
" returns an array with the calculated date in the form [year,month,day]
"-------------------------------------------------------------------------------

function! s:DateFromDOY(year, doy)
	let dim = [31, 28+s:Leapyear(a:year), 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

	let y = a:year
	let m = 1
	let d = a:doy

	while d > dim[m-1]
		let d = d - dim[m-1]
		let m = m + 1
	endwhile

	return [y,m,d]

endfunction


"-------------------------------------------------------------------------------
" DayOfWeek() - Calculate the day of the week with Sakamoto's methode
" Takes three integers 'year', 'month', 'day' as input and calculates the day
" of the week, where 0=Sunday, 1=Monday ..., 6=Saturday
"
" The alogrithm is taken from:
" https://en.wikipedia.org/wiki/Determination_of_the_day_of_the_week
"-------------------------------------------------------------------------------

function! s:DayOfWeek(year,month,day)
	let t = [0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4]
	let y = a:year
	let m = a:month
	let d = a:day
    if m<3
        let y-=1
	endif
	let dow = float2nr((y + y/4 - y/100 + y/400 + t[m-1] + d) % 7)
	return dow
endfunction


"-------------------------------------------------------------------------------
" KW() - Calculate the calendar week according to DIN 1335
" Takes three integers for 'year', 'month' and 'day' as input and returns the 
" calender week for the given date (1..53)
"
" The algorithm is taken from:
" http://www.a-m-i.de/tips/datetime/datetime.php
"-------------------------------------------------------------------------------

function! s:KW(year, month, day)

	let rc = 0   " ResultCode (KW)

	let doy = s:DayOfYear(a:year,a:month,a:day)
	let wd_jan1 = s:DayOfWeek(a:year,1,1)

	" Edge cases: Saturday and Sunday
	" Adjust so Jan 1 is treated as a negative offset when it's 
	" Friday/Saturday/Sunday
	" (ensures the week starts with Monday as per ISO/DIN 1355)

	if wd_jan1 >=5
		let wd_jan1 = wd_jan1 - 7
	endif

	" Edge case: Calendar week from previous year
	" If the date belongs to the last week of the previous year
	if doy + wd_jan1 <= 1
		let doy = s:DayOfYear(a:year - 1, 12, 31)
		let wd_jan1 = s:DayOfWeek(a:year - 1, 12, 31)
		if wd_jan1 >= 5
			let wd_jan1 = wd_jan1 - 7
		endif
	endif

	let rc = ((doy + wd_jan1 + 5) / 7)

	" Edge case: Calendar week 53, only if the year starts with a
	" Thursday (or a Wednesday if it is a leap year).
	if rc == 53
		if (wd_jan1 == 4) || (wd_jan1 == -3) || ((wd_jan1 == 3) && s:Leapyear(a:year)) || ((wd_jan1 == -4) && s:Leapyear(a:year))
			let rc = rc
		else
			let rc = 1
		endif
	endif

	return rc

endfunction


"-------------------------------------------------------------------------------
" TextCal() - Create the text calendar
" Takes an integer for the 'year' as an input and creates a daily calendar
" in a new buffer.
"-------------------------------------------------------------------------------

function! s:TextCal(year)

	let y = str2nr(a:year)

	" Don't allow years < 2000
	if (y == 0 ) || (y < 2000)
		echohl ErrorMsg | echo "Invalid year (must be >= 2000)" | echohl None
		return
	endif

	let monate = { 1: 'Januar', 2: 'Februar', 3: 'Maerz', 4: 'April', 5: 'Mai', 6: 'Juni', 7: 'Juli', 8: 'August', 9: 'September', 10: 'Oktober', 11: 'November', 12: 'Dezember' }
	let dim = [31, 28+s:Leapyear(y), 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	let dow = ['Son','Mon','Die','Mit', 'Don', 'Fre', 'Sam']

	let [oy,om,od] = s:Easter(y)
	let ot = s:DayOfYear(oy,om,od)

	let feiertage = { 
		\ s:DayOfYear(y,1,1) : 'Neujahr', 
		\ s:DayOfYear(y,1,6) : 'Dreikoenig',
		\ ot-2 : 'Karfreitag',
		\ ot : 'Ostern',
		\ ot+1 : 'Ostermontag',
		\ s:DayOfYear(y,5,1): 'Maifeiertag',
		\ ot+39: 'Himmelfahrt',
		\ ot+49: 'Pfingstsonntag',
		\ ot+50: 'Pfingstmontag',
		\ ot+60: 'Fronleichnam',
		\ s:DayOfYear(y,10,3): 'Deutsche Einh.',
		\ s:DayOfYear(y,11,1): 'Allerheiligen',
		\ s:DayOfYear(y,12,24): 'Heiligabend',
		\ s:DayOfYear(y,12,25): 'Weihnachten',
		\ s:DayOfYear(y,12,26): 'Weihnachten',
		\ s:DayOfYear(y,12,31): 'Silvester'
		\ }

	" Check for bridge days
	" Only considering Monday and Friday as realistic bridge days
	let brueckentage = {}
	for k in keys(feiertage)
		let [fty,ftm,ftd] = s:DateFromDOY(y, k)
		let wd = s:DayOfWeek(fty,ftm,ftd)
		" Bridge day on Monday
		if (wd == 2) && (!has_key(feiertage,k-1))
			let brueckentage[k-1] = '(Brueckentag)'
		endif
		" Bridge day on Friday
		if (wd == 4) && (!has_key(feiertage,k+1))
			let brueckentage[k+1] = '(Brueckentag)'
		endif
	endfor


	" Add modeline with my custom settings
	let tcal = ''
	let tcal = tcal . "################################################################################\n"
	let tcal = tcal . "# vim: set syntax=rs_outliner fdm=marker tw=0 nohls noai nocuc nocin:\n"
	let tcal = tcal . "################################################################################\n\n"

	let m = 0
	let wd = 0
	while m < 12
		let m = m + 1

		let l = '***** '. monate[m].' '.y.' '
		let ln = 80 - 6 - strlen(monate[m]) - 6 - 3
		while ln > 0
			let l = l .'*'
			let ln = ln - 1
		endwhile

		let tcal = tcal . l ."{{{\n"

		let d = 0
		while d < dim[m-1]
			let d = d + 1
			let doy = s:DayOfYear(y, m, d)

			" Check for holiday
			if has_key(feiertage, doy)
				let feiertag = feiertage[doy]
			else
				let feiertag = ''
			endif
			
			" Check for bridge day
			if has_key(brueckentage, doy)
				let optinf = brueckentage[doy]
			else
				let optinf = ''
			endif

			let wd = s:DayOfWeek(y, m, d)
			if (wd == 1) || (doy == 1)
				let kw = s:KW(y, m, d)
				let l = printf("KW%02d %02d %s : %s%s", kw, d, dow[wd], feiertag, optinf)
			else
				let l = printf("     %02d %s : %s%s", d, dow[wd], feiertag, optinf)
			endif
			let tcal = tcal . l . "\n"
		endwhile

		let tcal = tcal ."}}}\n"

	endwhile

	new
	setlocal noswapfile modifiable
	0put =tcal
	normal! gg
	silent execute 'file' fnameescape('textcal-' . a:year . '.txt')

endfunction


"-------------------------------------------------------------------------------
" RunTextCal() - Wrapper function to allow running without giving a year as 
" parameter. If no year is given, the current year is used.
"-------------------------------------------------------------------------------

function! textcal#RunTextCal(...) abort
    if a:0 == 0
        let year = strftime('%Y')
    else
        let year = a:1
    endif
    call s:TextCal(year)
endfunction


" Restore cpo
let &cpo = s:cpo_sav
unlet s:cpo_sav

"<EOF>
