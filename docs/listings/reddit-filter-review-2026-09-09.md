# Reddit filter review — 2026-09-09

Status: the r/obs post is filtered; the r/SideProject post remains publicly visible.
The cause is unknown. Bernhard read and sent the prepared modmail on 2026-09-09,
then explicitly confirmed the send in the conversation. Moderator review is pending;
no restoration or fix has been verified.

## Observed state

- [r/obs setup guide](https://www.reddit.com/r/obs/comments/1wbgklm/iphone_into_obs_over_usb_on_macos_i_built_a_free/):
  the logged-in Chrome author view shows the post body and the notice,
  "Sorry, this post was removed by Reddit’s filters." Public retrieval does not show
  the body. Author visibility therefore does not establish public visibility.
- [r/SideProject creator post](https://www.reddit.com/r/SideProject/comments/1wbgju8/my_iphone_kept_disconnecting_while_recording/):
  publicly visible when checked, without the same removal notice.
- The notification inbox and legacy message inbox were empty. No specific removal
  reason or enforcement message was available to the author.

The notice identifies filtering but does not reveal the trigger. There is no evidence
that an AI detector caused it. There is also no basis to attribute it to a particular
link, wording choice, account property or subreddit rule. The visible SideProject post
does not establish why r/obs handled its post differently.

## Review requested

The sent request asks the r/obs moderators to review the existing post, explain any
reason they can see, and approve it if it meets their rules. Keep the existing
permalink while seeking review. No duplicate submission is needed for that request.

Reddit's [post visibility guidance](https://support.reddithelp.com/hc/en-us/articles/360045989712-Why-can-t-I-see-my-post)
describes several possible causes and directs authors to modmail when a removal may
need moderator review. Those general possibilities are not a diagnosis of this post.
The [moderation queue documentation](https://support.reddithelp.com/hc/en-us/articles/15484440494356-Moderation-Queue)
explains that moderators can approve previously filtered content and make it visible
again. Approval remains their decision; it is not guaranteed.

## Prepared modmail — sent by Bernhard

**To:** r/obs moderators

**Subject:** Could you review my TetherCam setup guide caught by Reddit's filters?

Hi mods,

My TetherCam setup guide is showing "removed by Reddit's filters", but I haven't received a specific reason:

https://www.reddit.com/r/obs/comments/1wbgklm/iphone_into_obs_over_usb_on_macos_i_built_a_free/

I'm the developer. It's a free, open-source iPhone-to-OBS plugin for macOS. The post includes the installation steps, requirements and troubleshooting, and is flaired Guide. I read the rule allowing useful how-to links and tried to keep it relevant to that.

Could you check which filter or rule was involved and approve the existing post if it fits? If something needs changing, I'm happy to edit it.

Thanks,
Bernhard

## Completion evidence still needed

Send evidence: Bernhard explicitly confirmed that he read and sent the message.
The composer was subsequently empty. An independent sent-message entry could not
be retrieved: Reddit's `/message/sent/` route returned "page not found". No second
message was sent.

A moderator reply or verified public restoration of the existing r/obs post would
be a new result to record separately. Neither has occurred in the evidence available
for this report.

## Additional community round

Bernhard subsequently requested more relevant communities. The r/macapps App Pile
comment is publicly visible, including its image, verified in logged-out Chrome:
https://www.reddit.com/r/macapps/comments/1w4brkd/comment/p8ppyzr/

Additional posts in r/microsaas and r/IMadeThis were submitted and immediately
filtered with the same generic notice. This does not establish a shared trigger.
The r/SideProject post remained visible in logged-out Chrome. No specific removal
reason appeared in notifications. See `reddit-community-expansion-2026-09-09.md` for
the exact posts, additional account observations, and decisions for all candidates.

Further submissions were stopped after the repeated filtering. After Bernhard's
explicit authorization, the two additional moderator requests were each sent once
through Chrome on 2026-09-09. Their unchanged texts and exact send evidence are in
`reddit-additional-modmail-drafts.md`: MicroSaaS showed "Message sent" and reset the
composer; IMadeThis cleared all fields after Send without an error, but no second
success toast was recorded. Moderator review and any restoration remain pending.
No duplicate posts or moderator requests were sent.
