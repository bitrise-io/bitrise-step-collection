Bitrise Verified Step Collection
=======================

Bitrise's Verified Step Collection - a verified set of StepLib steps used on [Bitrise](http://www.bitrise.io/).

You can read more about StepLib [here](https://github.com/steplib/steplib).

# Want to propose a new Step?

Do you want to add your own step to our verified collection? Great!
Here's what you have to do:

If you want to propose a new Step to be included in the Bitrise Collection
you'll first have to add your Step to the Open [StepLib](https://github.com/steplib/steplib)
collection, then create an issue [here on GitHub](https://github.com/bitrise-io/bitrise-step-collection) with the *[proposal]* prefix.

**Every step in our collection is verified by one of our developers** and we'll fork your
repository to maintain control over the verified code. We check for step version updates regularly
but if you want to notify us about a new version of your step you can either send a *Pull Request*
or add a new issue with the *[update]* prefix.


# Verification Requirements (for developers working on the Bitrise Collection)

* every repository have to be forked if it's not owned by the [bitrise-io team](https://github.com/bitrise-io) on GitHub, and the verified Step's repository have to point to a repository owned by the [bitrise-io team](https://github.com/bitrise-io).
* every Step should be tested on Bitrise with the [step-tester-and-validator](https://github.com/bitrise-io/steps-step-tester-and-validator) step.