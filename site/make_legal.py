"""Writes the DeskOrg legal pages (site/pages/privacy-policy.html, terms-of-use.html, disclaimer.html).
Run from the DeskOrg folder:  python -X utf8 site/make_legal.py   (then scripts-local/make_site.py builds docs/)"""
import os

HERE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'pages')
HEAD = '''<!--TITLE {t}-->
<!--DESC {d}-->
<!--LD
{{"@context":"https://schema.org","@graph":[{{"@type":"WebPage","name":"{n}","url":"{{{{SITE}}}}{slug}.html"}},
 {{"@type":"BreadcrumbList","itemListElement":[{{"@type":"ListItem","position":1,"name":"DeskOrg","item":"{{{{SITE}}}}"}},{{"@type":"ListItem","position":2,"name":"{n}","item":"{{{{SITE}}}}{slug}.html"}}]}}]}}
-->
<section class="ph">
  <div class="wrap">
    <p class="crumbs"><a href="/">DeskOrg</a> › {n}</p>
    <h1>{n}</h1>
    <p>{lead}</p>
  </div>
</section>
<div class="wrap doc">
  <nav class="toc" aria-label="On this page"><b>On this page</b>{toc}</nav>
  <article class="prose">
    <p class="updated">Last updated: 2 November 2026</p>
'''
FOOT = '''    <h2 id="contact">Contact</h2>
    <p>Questions about this page: <a href="https://www.niveshsahayak.in/p/contact.html">contact Nivesh Sahayak</a> or call <a href="tel:+918054009300">+91 80540 09300</a>.</p>
  </article>
</div>
'''


def page(slug, n, t, d, lead, secs):
    toc = ''.join('<a href="#%s">%s</a>' % (i, h) for i, h, _ in secs) + '<a href="#contact">Contact</a>'
    body = ''.join('    <h2 id="%s">%s</h2>\n%s\n' % (i, h, b) for i, h, b in secs)
    with open(os.path.join(HERE, slug + '.html'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(HEAD.format(t=t, d=d, n=n, slug=slug, lead=lead, toc=toc) + body + FOOT)


page('privacy-policy', 'Privacy Policy', 'DeskOrg Privacy Policy: the App Collects Nothing',
     'DeskOrg runs only on your PC and collects no personal data. How this website handles fonts, sponsor cards and hosting logs, and your choices.',
     'The short version: the DeskOrg app collects nothing, and this website keeps no data about you.',
     [('app', 'The DeskOrg app', '''    <p>DeskOrg works entirely on your own computer. It reads file names and types on your desktop and moves files into folders according to your rules. It does <b>not</b> upload, sync, share or sell any file, file name or personal data, and it has no account, analytics or advertising inside.</p>
    <ul><li><b>Your rules and settings</b> are saved in your own Windows user profile.</li><li><b>The activity log</b> (what was moved and where) is a file on your PC that only you can see.</li><li>The app only goes online when you click a link in it (for example to this website); your browser then opens it.</li></ul>'''),
      ('site', 'This website', '''    <p>This website has no sign-up, no contact form, no analytics and no advertising cookies. We don't ask for or store personal information. A few services make the pages work:</p>
    <ul><li><b>Hosting:</b> the site is served by GitHub Pages. Like any web host, GitHub may record technical data such as your IP address and browser in its server logs for security. See <a href="https://docs.github.com/site-policy/privacy-policies/github-general-privacy-statement">GitHub's privacy statement</a>.</li>
    <li><b>Fonts:</b> the page fonts load from Google Fonts, so your browser contacts Google's servers. See <a href="https://policies.google.com/privacy">Google's privacy policy</a>.</li>
    <li><b>Downloads:</b> the installer is downloaded from GitHub Releases.</li>
    <li><b>Credit badge:</b> a small script from assets.niveshsahayak.in draws the footer credit. It stores nothing.</li></ul>'''),
      ('sponsors', 'Sponsor cards', '''    <p>The home page shows two sponsor cards. Their text and pictures load from share.groupchaton.com and Google's image servers; nothing about you is sent with them. Whether you see offers meant for India is decided from your device's time zone, inside your browser. If you click a sponsor card you go to that company's website, which has its own privacy policy and may record that you came from us (a referral).</p>'''),
      ('children', 'Children', '''    <p>DeskOrg and this website are not directed at children under 13, and we don't knowingly collect personal information from anyone.</p>'''),
      ('changes', 'Changes', '''    <p>If this policy changes, we update this page and the date at the top.</p>''')])

page('terms-of-use', 'Terms of Use', 'DeskOrg Terms of Use',
     'The terms for using the DeskOrg app and this website: the MIT licence, fair use, sponsor links and limits of responsibility.',
     'Simple terms for a free app. By downloading DeskOrg or using this website you agree to them.',
     [('licence', 'The DeskOrg licence', '''    <p>DeskOrg is free software released under the <a href="/LICENSE.txt">MIT licence</a>. You may use, copy, modify and share it, including for work, as long as the licence notice stays with copies. The licence is the legal licence for the software; these terms cover this website and the official downloads.</p>'''),
      ('use', 'Using the app', '''    <ul><li>DeskOrg moves files on your PC according to the rules you set. You are responsible for your rules and for keeping backups of important files.</li><li>Download DeskOrg only from this website or its GitHub Releases page; copies from elsewhere may be modified.</li><li>Don't use DeskOrg to manage computers or files you don't have permission to manage.</li></ul>'''),
      ('site', 'Using this website', '''    <p>You may read, link to and share this website. Don't copy its design or text to pretend to be DeskOrg, and don't try to disrupt or overload the site.</p>'''),
      ('sponsors', 'Sponsor links', '''    <p>Some cards on this website are sponsored and link to other companies. Their offers, products and terms are their own; we don't control them and aren't responsible for them. We may earn a referral reward when you sign up through them, at no extra cost to you.</p>'''),
      ('warranty', 'No warranty and limits of responsibility', '''    <p>DeskOrg and this website are provided "as is", without warranty of any kind, as the MIT licence says. To the extent the law allows, Nivesh Sahayak is not liable for any loss of data, files, time or profit arising from using DeskOrg or this website.</p>'''),
      ('law', 'Law and changes', '''    <p>These terms are governed by the laws of India. We may update them; the date at the top shows the latest version, and continuing to use the app or site means you accept the update.</p>''')])

page('disclaimer', 'Disclaimer', 'DeskOrg Disclaimer',
     'Important notes about DeskOrg: it moves files on your PC, keep backups, the Windows warning, sponsor links and trademarks.',
     'Please read this before you rely on DeskOrg for important files.',
     [('files', 'Files on your PC', '''    <p>DeskOrg moves files from your desktop into folders using rules you control. It does not delete files, but any tool that moves files can surprise you if a rule is set up differently from what you expect. Check your rules, use <b>Activity &amp; Logs</b> to find moved files, and keep regular backups of anything important.</p>'''),
      ('warning', 'The Windows warning', '''    <p>DeskOrg is signed with its own certificate, not a commercial one, so Windows SmartScreen or your antivirus may show a caution the first time. That warning is about the publisher being new to Windows, not about anything found in the app. If you are unsure, download only from this website and see <a href="/setup-help.html">Install help</a>.</p>'''),
      ('info', 'Information on this website', '''    <p>Guides and help here are written in good faith and kept up to date, but Windows and other software change, so screens and messages on your PC may look a little different.</p>'''),
      ('sponsors', 'Sponsored links', '''    <p>Cards marked <b>Sponsored</b> link to other companies' offers, and we may earn a referral reward. We don't endorse, guarantee or take responsibility for third-party products, prices or offers; read their terms before you sign up.</p>'''),
      ('tm', 'Trademarks', '''    <p>Windows and Microsoft are trademarks of Microsoft Corporation. DeskOrg is an independent app and is not affiliated with, endorsed by or sponsored by Microsoft. Other names belong to their owners.</p>''')])
print('written')
