# Developing Qpsmtpd

## Mailing List

All qpsmtpd development happens on the qpsmtpd mailing list.

Subscribe by sending mail to qpsmtpd-subscribe@perl.org

## Git

We use git for version control.

The master repository is at git://github.com/smtpd/qpsmtpd.git

We suggest using github to host your repository -- it makes your
changes easily accessible for pulling into the master.  After you
create a github account, go to
[the master repository](http://github.com/smtpd/qpsmtpd/tree/master) and click on the "fork"
button to get your own repository.

### Making a working Copy

    git clone git@github.com:username/qpsmtpd.git qpsmtpd

will check out your copy into a directory called qpsmtpd

### Making a branch for your change

As a general rule, you'll be better off if you do your changes on a
branch - preferably a branch per unrelated change.

You can use the `git branch` command to see which branch you are on.

The easiest way to make a new branch is

    git checkout -b topic/my-great-change

This will create a new branch with the name "topic/my-great-change"
(and your current commit as the starting point).

### Committing a change

Edit the appropriate files, and be sure to run the test suite.

    emacs lib/Qpsmtpd.pm # for example
    perl Makefile.PL
    make test

When you're ready to check it in...

    git add lib/Qpsmtpd.pm     # to let git know you changed the file
    git add --patch plugin/tls # interactive choose which changes to add
    git diff --cached          # review changes added
    git commit                 # describe the commit
    git log -p                 # review your commit a last time
    git push origin            # to send to github

### Commit Descriptions

Though not required, it's a good idea to begin the commit message with
a single short (less than 50 character) line summarizing the change,
followed by a blank line and then a more thorough description. Tools
that turn commits into email, for example, use the first line on the
Subject: line and the rest of the commit in the body.
(From: [git-commit(1)](http://man.he.net/man1/git-commit))

### Submit patches by mail

The best way to submit patches to the project is to send them to the
mailing list for review.  Use the `git format-patch` command to
generate patches ready to be mailed. For example:

    git format-patch HEAD~3

will put each of the last three changes in files ready to be mailed
with the `git send-email` tool (it might be a good idea to send them
to yourself first as a test).

Sending patches to the mailing list is the most effective way to
submit changes, although it helps if you at the same time also commit
them to a git repository (for example on github).

### Merging changes back in from the master repository

Tell git about the master repository.  We're going to call it 'smtpd'
for now, but you could call it anything you want.  You only have to do
this once.

    git remote add smtpd git://github.com/smtpd/qpsmtpd.git

Pull in data from all remote branches

    git remote update

Forward-port local commits to the updated upstream head

    git rebase smtpd/master

If you have a change that conflicts with an upstream change (git will
let you know) you have two options.

Manually fix the conflict and then do

    git add some/file
    git commit

Or if the conflicting upstream commit did the same logical change then
you might want to just skip the local change:

    git rebase --skip

Be sure to decide whether you're going to skip before you merge, or
you might get yourself into an odd situation.

Conflicts happen because upstream committers may make minor tweaks to
your change before applying it.

### Throwing away changes

If you get your working copy into a state you don't like, you can
always revert to the last commit:

    git reset --hard HEAD

Or throw away your most recent commit:

    git reset --hard HEAD^

If you make a mistake with this, git is pretty good about keeping your
commits around even as you merge, rebase and reset away.  This log of
your git changes is called with "git reflog".

### Applying other peoples changes

If you get a change in an email with the patch, one easy way to apply
other peoples changes is to use `git am`.  That will go ahead and
commit the change.  To modify it, you can use `git commit --amend`.

If the changes are in a repository, you can add that repository with
"git remote add" and then either merge them in with "git merge" or
pick just the relevant commits with "git cherry-pick".
