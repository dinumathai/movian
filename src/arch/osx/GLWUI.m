/*
 *  Copyright (C) 2007-2015 Lonelycoder AB
 *
 *  This program is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 *  This program is also available under a commercial proprietary license.
 *  For more information, contact andreas@lonelycoder.com
 */
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>

#include "main.h"
#include "osx.h"
#include "src/ui/glw/glw.h"
#include "navigator.h"

#include "networking/net.h"
#include "prop/prop_proxy.h"

@interface GLWWindow : NSWindow
{
}
-(BOOL)canBecomeKeyWindow;
@end


@implementation GLWWindow
-(BOOL)canBecomeKeyWindow
{
  return YES;
}


@end


@interface GLWUI (hidden)

- (void)openWin;
- (void)toggleFullscreen;
- (void)setFullWindow:(BOOL)on;

@end



@implementation GLWUI

- (BOOL)windowShouldClose:(NSNotification *)notification {
  return YES;
}

- (void)windowWillClose:(NSNotification *)notification {
  [self shutdown];
}

- (void)windowDidMiniaturize:(NSNotification *)notification
{
  [view windowDidMiniaturize:notification];
  minimized = YES;
}

- (void)windowDidDeminiaturize:(NSNotification *)notification
{
  [view windowDidDeminiaturize:notification];
  minimized = NO;
}



/**
 *
 */
- (void)openWin:(BOOL)asfullscreen
{
  NSRect frame;

  fullscreen = asfullscreen;

  if(fullscreen) {

    frame = [[NSScreen mainScreen] frame];
    window = [[GLWWindow alloc] initWithContentRect: frame
					    styleMask:NSBorderlessWindowMask
					      backing:NSBackingStoreBuffered
						defer:NO];

    [window setLevel:NSMainMenuWindowLevel+1];
    [window setOpaque:YES];
    [window setHidesOnDeactivate:YES];

  } else {

    frame = NSMakeRect( 100., 100., 1280./1.5, 720./1.5 );

    window = [[GLWWindow alloc]
			 initWithContentRect:frame
				   styleMask:NSTitledWindowMask | NSClosableWindowMask | NSMiniaturizableWindowMask | NSResizableWindowMask
				     backing:NSBackingStoreBuffered
				       defer:NO];

     [window setTitle:title];
     [window setFrameAutosaveName:@"main"];
  }

  view = [[GLWView alloc] initWithFrame:frame:gr:fullscreen];
  [window setContentView:view];
  [window setDelegate:self];
  [window makeKeyAndOrderFront:nil];
  [window setAcceptsMouseMovedEvents:YES];

  [NSApp activateIgnoringOtherApps:YES];

}


/**
 *
 */
- (void)toggleFullscreen
{
  [view stop];
  [window close];
  [view release];
  [self openWin:!fullscreen];
}


/**
 *
 */
static void
eventsink(void *opaque, prop_event_t event, ...)
{
  GLWUI *ui = opaque;
  va_list ap;
  event_t *e;
  va_start(ap, event);

  switch(event) {
  case PROP_EXT_EVENT:
    e = va_arg(ap, event_t *);
    if(event_is_action(e, ACTION_FULLSCREEN_TOGGLE))
      [ui toggleFullscreen];
    break;

  default:
    break;
  }
  va_end(ap);
}


/**
 *
 */
-(void)setFullWindow:(BOOL)on
{
  if(fullwindow == on)
    return;

  fullwindow = on;

  if(on) {
    timer = CFRunLoopTimerCreate(NULL, CFAbsoluteTimeGetCurrent(), 3, 0, 0,
				 update_sys_activity, NULL);

    CFRunLoopAddTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);
  } else {
    CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), timer, kCFRunLoopCommonModes);
    CFRelease(timer);
    timer = NULL;
  }

}


/**
 *
 */
static void
set_fullwindow(void *opaque, int v)
{
  GLWUI *ui = opaque;
  [ui setFullWindow:(BOOL)v];
}


/**
 *
 */
static void
update_sys_activity(CFRunLoopTimerRef timer, void *info)
{
  UpdateSystemActivity(OverallAct);
}

static prop_t *stored_nav;


/**
 *
 */
- (id) init
{
  self = [super init];

  if(!self)
    return self;

  gr = calloc(1, sizeof(glw_root_t));

  gr->gr_prop_ui = prop_create_root("ui");


  if(gconf.remote_ui) {
    struct net_addr na;
    const char *errtxt;
    if(net_resolve(gconf.remote_ui, &na, &errtxt))
      exit(1);
    na.na_port = 42000;
    prop_t *p = prop_proxy_connect(&na);

    gr->gr_prop_nav =
      prop_get_by_name(PNVEC("remote", "navigators", "current"),
                       1,
                       PROP_TAG_NAMED_ROOT, p, "remote",
                       NULL);

    title = [[NSString alloc] initWithUTF8String: "Remote"];

  } else if(stored_nav != NULL) {
    gr->gr_prop_nav = stored_nav;
    stored_nav = NULL;
    title = [[NSString alloc] initWithUTF8String: "Showtime"];
  } else {
    gr->gr_prop_nav = nav_spawn();
    title = [[NSString alloc] initWithUTF8String: "Showtime"];
  }

  if(glw_init(gr)) {
    prop_destroy(gr->gr_prop_ui);
    free(gr);
    [title release];
    [self release];
    return nil;
  }

  evsub = prop_subscribe(0,
			 PROP_TAG_CALLBACK, eventsink, self,
			 PROP_TAG_NAME("ui", "eventSink"),
			 PROP_TAG_ROOT, gr->gr_prop_ui,
			 PROP_TAG_COURIER, mainloop_courier,
			 NULL);

  fullwindow = NO;


  fwsub = prop_subscribe(0,
			 PROP_TAG_CALLBACK_INT, set_fullwindow, self,
			 PROP_TAG_NAME("ui", "fullwindow"),
			 PROP_TAG_ROOT, gr->gr_prop_ui,
			 PROP_TAG_COURIER, mainloop_courier,
			 NULL);

  [self openWin:NO];

  glw_lock(gr);
  glw_load_universe(gr);
  glw_unlock(gr);

  return self;
}


/**
 * Shutdown this UI instance
 */
- (void)shutdown
{
  [view stop];

  glw_lock(gr);
  glw_unload_universe(gr);
  glw_unlock(gr);
  glw_reap(gr);
  glw_reap(gr);

  prop_unsubscribe(evsub);
  prop_unsubscribe(fwsub);

  glw_fini(gr);
  prop_destroy(gr->gr_prop_ui);
  if(stored_nav != NULL)
    prop_destroy(stored_nav);
  stored_nav = gr->gr_prop_nav;

  free(gr);

  [title release];
  [view release];
  [self release];
}

/**
 *
 */
- (void)dealloc
{
  [super dealloc];
}
@end
