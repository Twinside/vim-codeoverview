#!/usr/bin/env python

import pygtk
pygtk.require('2.0')
import gtk
import gio
import sys
import cairo
import os
from threading import *
from ctypes import *

class XRect:
    def __init__(self, x, y, w, h, b):
        self.x = x
        self.y = y
        self.width = w
        self.height = h
        self.border = b

class XWinQueryer:
    def __init__(self):
        self.lib = CDLL("libX11.so.6")

        self.xOpenDisplay = self.lib.XOpenDisplay
        self.xOpenDisplay.restype = c_void_p

        self.xGetGeometry = self.lib.XGetGeometry
        self.xGetGeometry.restype = c_int
        self.xGetGeometry.argtypes = [ c_void_p  # display
                                     , c_int     # drawable
                                     , POINTER(c_int)   # root back
                                     , POINTER(c_int)   # xBack
                                     , POINTER(c_int)   # yBack
                                     , POINTER(c_int)   # width back
                                     , POINTER(c_int)   # height back
                                     , POINTER(c_int)   # border width back
                                     , POINTER(c_int)   # depth back
                                     ]

    def getGeometry(self, windowId):
        display = self.openDisplay()
        print("ok " + str(windowId))
        rootBack = c_int(0)
        xp = c_int(0)
        yp = c_int(0)
        wp = c_int(0)
        hp = c_int(0)
        bp = c_int(0)
        dp = c_int(0)
        self.xGetGeometry( display
                         , windowId
                         , byref(rootBack)
                         , byref(xp)
                         , byref(yp)
                         , byref(wp)
                         , byref(hp)
                         , byref(bp)
                         , byref(dp) )
        print("After call")
        return XRect( xp.value, yp.value
                    , wp.value, hp.value
                    , bp.value )

    def openDisplay(self):
        return self.xOpenDisplay(c_char_p(0))

class Poller(Thread):
    def __init__(self, interval, function, args=[], kwargs={}):
        Thread.__init__(self)
        self.interval = interval
        self.args = args
        self.function = function
        self.kwargs = kwargs
        self.finished = Event()
 
    def run(self):
        while not self.finished.is_set():
            self.finished.wait(self.interval)
            if not self.finished.is_set():
                self.function(*self.args, **self.kwargs)
 
    def cancel(self):
        self.finished.set()

class OverViewImage:
    # when invoked (via signal delete_event), terminates the application.
    def close_application(self, widget, event, data=None):
        self.poller.cancel()
        gtk.main_quit()
        return False

    def windowTracker(self):
        if (self.windowId <= 0):
        	return

        rectInfo = self.windowQueryer.getGeometry(self.windowId)
        print("x:" + str(rectInfo.x) + " y:" + str(rectInfo.y) + " w:" + str(rectInfo.width) + " h:" + str(rectInfo.height))
        (winWidth, winHeight) = self.window.get_size()
        self.window.resize(winWidth, rectInfo.height)
        self.window.move(rectInfo.x - winWidth - rectInfo.border, rectInfo.y)


    # is invoked when the button is clicked.  It just prints a message.
    def image_clicked(self, widget, data=None):
        if not self.initiated:
            return
        yPos = int(data.y)
        lineNum = int(yPos * self.imageHeight / self.actualHeight)
        textVersion = ''.join(map(lambda n: '\\\\[' + n + ']', str(lineNum)))
        command = 'xvkbd -text "' + textVersion + 'ggzz" -window ' + str(self.windowId)

        relativeHeight = (self.realBottom - self.realTop) / 2
        self.realTop = max(0, yPos - relativeHeight)
        self.realBottom = yPos + relativeHeight
        os.system(command)
        self.drawArea.queue_draw()

    def updateViewSizeInformation(self, picture):
        (width, height) = (picture.get_width(), picture.get_height())
        self.realTop = float(self.beginning) / height * self.actualHeight;
        self.realBottom = float(self.ending) / height * self.actualHeight;
        self.imageHeight = height
        
    def updateImage(self, newFilename):
        pixbuf = gtk.gdk.pixbuf_new_from_file(newFilename)

        imageWidth = pixbuf.get_width()
        imageHeight = pixbuf.get_height()

        (width, height) = self.window.get_size()

        width = min( imageWidth, width )
        height = min( imageHeight, height )

        self.actualHeight = height
        self.updateViewSizeInformation(pixbuf)

        self.codePixbuf = pixbuf
        self.scaledPixbuf = pixbuf.scale_simple( width, height, gtk.gdk.INTERP_BILINEAR)
        self.drawArea.queue_draw()

    def info_changed(self, monitor, fileObj, other_file = None, event_type = None, data = None):
        wakeFile = open(self.watchedFilename,"r")
        line = wakeFile.read()
        wakeFile.close()

        if line[-1] == '\n':
            line = line[0:-1]

        if line == "quit":
        	gtk.main_quit()
        	return

        [begin, end, backColor, viewRectColor, winId, winX, winY, imageFile] = line.split("?")
        self.beginning = int(begin)
        self.ending = int(end)
        self.updateImage(imageFile)
        self.windowId = int(winId)
        self.backColor = gtk.gdk.color_parse(backColor)
        
        self.rectColor = gtk.gdk.color_parse(viewRectColor)
        self.initiated = True

    def area_draw(self, area, event):
        if not self.initiated:
        	return

        (width, wholeHeight) = self.drawArea.window.get_size()
        height = self.realBottom - self.realTop

        cr = self.drawArea.window.cairo_create()

        cr.set_source_rgba(self.backColor.red_float, 
                           self.backColor.green_float, 
                           self.backColor.blue_float, 1.0)
        cr.rectangle(0, 0, width, wholeHeight)
        cr.fill()

        cr.set_source_rgba(1.0, 1.0, 1.0, 1.0)
        cr.set_source_pixbuf(self.scaledPixbuf, 0, 0)
        cr.paint()

        cr.set_source_rgba(self.rectColor.red_float, 
                           self.rectColor.green_float, 
                           self.rectColor.blue_float, 0.6)
        cr.rectangle(0, int(self.realTop), width, int(height))
        cr.fill()
        

    def __init__(self, title, filename):
        self.initiated = False

        self.watchedFilename = filename
        self.gFile = gio.File(filename)
        self.gFileMonitor = self.gFile.monitor_file()
        self.gFileMonitor.connect("changed", self.info_changed)

        # create the main window, and attach delete_event signal to terminating
        # the application
        self.window = gtk.Window(gtk.WINDOW_TOPLEVEL)
        self.window.connect("delete_event", self.close_application)
        self.window.set_border_width(0)
        self.window.resize(80, 500)
        self.window.move(0, 0)
        self.window.set_title(title)
        self.window.set_icon(None)
        self.window.show()

        self.backColor = gtk.gdk.color_parse('#FFFFFF')

        self.drawArea = gtk.DrawingArea()
        self.drawArea.set_events(gtk.gdk.BUTTON_PRESS_MASK | gtk.gdk.BUTTON_RELEASE_MASK)
        self.drawArea.connect("expose-event", self.area_draw )
        self.drawArea.connect("button-release-event", self.image_clicked )
        self.drawArea.show()

        self.window.add(self.drawArea)

        self.windowQueryer = XWinQueryer()
        #self.poller = Poller(1.0, self.windowTracker)
        #self.poller.start()


if __name__ == "__main__":
    watchedFilename = "/tmp/overviewFile" + sys.argv[1] + '.txt'
    OverViewImage(sys.argv[1], watchedFilename)
    gtk.main()

