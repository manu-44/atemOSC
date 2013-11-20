/* -LICENSE-START-
** Copyright (c) 2011 Blackmagic Design
**
** Permission is hereby granted, free of charge, to any person or organization
** obtaining a copy of the software and accompanying documentation covered by
** this license (the "Software") to use, reproduce, display, distribute,
** execute, and transmit the Software, and to prepare derivative works of the
** Software, and to permit third-parties to whom the Software is furnished to
** do so, all subject to the following:
** 
** The copyright notices in the Software and this entire statement, including
** the above license grant, this restriction and the following disclaimer,
** must be included in all copies of the Software, in whole or in part, and
** all derivative works of the Software, unless such copies or derivative
** works are solely in the form of machine-executable object code generated by
** a source language processor.
** 
** THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
** IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
** FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
** SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
** FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
** ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
** DEALINGS IN THE SOFTWARE.
** -LICENSE-END-
*/

#import "SwitcherPanelAppDelegate.h"
#include <libkern/OSAtomic.h>
#include <string>
#import "AMSerialPortList.h"
#import "AMSerialPortAdditions.h"

static inline bool	operator== (const REFIID& iid1, const REFIID& iid2)
{
	return CFEqual(&iid1, &iid2);
}

// Callback class for monitoring property changes on a mix effect block.
class MixEffectBlockMonitor : public IBMDSwitcherMixEffectBlockCallback
{
public:
	MixEffectBlockMonitor(SwitcherPanelAppDelegate* uiDelegate) : mUiDelegate(uiDelegate), mRefCount(1) { }
    
protected:
	virtual ~MixEffectBlockMonitor() { }
    
public:
	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, LPVOID *ppv)
	{
		if (!ppv)
			return E_POINTER;
		
		if (iid == IID_IBMDSwitcherMixEffectBlockCallback)
		{
			*ppv = static_cast<IBMDSwitcherMixEffectBlockCallback*>(this);
			AddRef();
			return S_OK;
		}
		
		if (CFEqual(&iid, IUnknownUUID))
		{
			*ppv = static_cast<IUnknown*>(this);
			AddRef();
			return S_OK;
		}
		
		*ppv = NULL;
		return E_NOINTERFACE;
	}
    
	ULONG STDMETHODCALLTYPE AddRef(void)
	{
		return ::OSAtomicIncrement32(&mRefCount);
	}
    
	ULONG STDMETHODCALLTYPE Release(void)
	{
		int newCount = ::OSAtomicDecrement32(&mRefCount);
		if (newCount == 0)
			delete this;
		return newCount;
	}
	
	HRESULT PropertyChanged(BMDSwitcherMixEffectBlockPropertyId propertyId)
	{
		switch (propertyId)
		{
			case bmdSwitcherMixEffectBlockPropertyIdProgramInput:
				[mUiDelegate performSelectorOnMainThread:@selector(updateProgramButtonSelection) withObject:nil waitUntilDone:YES];
				break;
			case bmdSwitcherMixEffectBlockPropertyIdPreviewInput:
				[mUiDelegate performSelectorOnMainThread:@selector(updatePreviewButtonSelection) withObject:nil waitUntilDone:YES];
				break;
			case bmdSwitcherMixEffectBlockPropertyIdInTransition:
				[mUiDelegate performSelectorOnMainThread:@selector(updateInTransitionState) withObject:nil waitUntilDone:YES];
				break;
			case bmdSwitcherMixEffectBlockPropertyIdTransitionPosition:
				[mUiDelegate performSelectorOnMainThread:@selector(updateSliderPosition) withObject:nil waitUntilDone:YES];
				break;
			case bmdSwitcherMixEffectBlockPropertyIdTransitionFramesRemaining:
				[mUiDelegate performSelectorOnMainThread:@selector(updateTransitionFramesTextField) withObject:nil waitUntilDone:YES];
				break;
			case bmdSwitcherMixEffectBlockPropertyIdFadeToBlackFramesRemaining:
				[mUiDelegate performSelectorOnMainThread:@selector(updateFTBFramesTextField) withObject:nil waitUntilDone:YES];
				break;
			default:	// ignore other property changes not used for this sample app
				break;
		}
		return S_OK;
	}
    
private:
	SwitcherPanelAppDelegate*		mUiDelegate;
	int								mRefCount;
};

// Monitor the properties on Switcher Inputs.
// In this sample app we're only interested in changes to the Long Name property to update the PopupButton list
class InputMonitor : public IBMDSwitcherInputCallback
{
public:
	InputMonitor(IBMDSwitcherInput* input, SwitcherPanelAppDelegate* uiDelegate) : mInput(input), mUiDelegate(uiDelegate), mRefCount(1)
	{
		mInput->AddRef();
		mInput->AddCallback(this);
	}
    
protected:
	~InputMonitor()
	{
		mInput->RemoveCallback(this);
		mInput->Release();
	}
	
public:
	// IBMDSwitcherInputCallback interface
	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, LPVOID *ppv)
	{
		if (!ppv)
			return E_POINTER;
		
		if (iid == IID_IBMDSwitcherInputCallback)
		{
			*ppv = static_cast<IBMDSwitcherInputCallback*>(this);
			AddRef();
			return S_OK;
		}
		
		if (CFEqual(&iid, IUnknownUUID))
		{
			*ppv = static_cast<IUnknown*>(this);
			AddRef();
			return S_OK;
		}
		
		*ppv = NULL;
		return E_NOINTERFACE;
	}
    
	ULONG STDMETHODCALLTYPE AddRef(void)
	{
		return ::OSAtomicIncrement32(&mRefCount);
	}
    
	ULONG STDMETHODCALLTYPE Release(void)
	{
		int newCount = ::OSAtomicDecrement32(&mRefCount);
		if (newCount == 0)
			delete this;
		return newCount;
	}
    
	HRESULT PropertyChanged(BMDSwitcherInputPropertyId propertyId)
	{
		switch (propertyId)
		{
			case bmdSwitcherInputPropertyIdLongName:
				[mUiDelegate performSelectorOnMainThread:@selector(updatePopupButtonItems) withObject:nil waitUntilDone:YES];
			default:	// ignore other property changes not used for this sample app
				break;
		}
		
		return S_OK;
	}
	IBMDSwitcherInput* input() { return mInput; }
	
private:
	IBMDSwitcherInput*			mInput;
	SwitcherPanelAppDelegate*	mUiDelegate;
	int							mRefCount;
};

// Callback class to monitor switcher disconnection
class SwitcherMonitor : public IBMDSwitcherCallback
{
public:
	SwitcherMonitor(SwitcherPanelAppDelegate* uiDelegate) :	mUiDelegate(uiDelegate), mRefCount(1) { }
    
protected:
	virtual ~SwitcherMonitor() { }
	
public:
	// IBMDSwitcherCallback interface
	HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, LPVOID *ppv)
	{
		if (!ppv)
			return E_POINTER;
		
		if (iid == IID_IBMDSwitcherCallback)
		{
			*ppv = static_cast<IBMDSwitcherCallback*>(this);
			AddRef();
			return S_OK;
		}
		
		if (CFEqual(&iid, IUnknownUUID))
		{
			*ppv = static_cast<IUnknown*>(this);
			AddRef();
			return S_OK;
		}
		
		*ppv = NULL;
		return E_NOINTERFACE;
	}
    
	ULONG STDMETHODCALLTYPE AddRef(void)
	{
		return ::OSAtomicIncrement32(&mRefCount);
	}
    
	ULONG STDMETHODCALLTYPE Release(void)
	{
		int newCount = ::OSAtomicDecrement32(&mRefCount);
		if (newCount == 0)
			delete this;
		return newCount;
	}
	
	// Switcher events ignored by this sample app
	HRESULT STDMETHODCALLTYPE	Notify(BMDSwitcherEventType eventType) { return S_OK; }
	
	HRESULT STDMETHODCALLTYPE	Disconnected(void)
	{
		[mUiDelegate performSelectorOnMainThread:@selector(switcherDisconnected) withObject:nil waitUntilDone:YES];
		return S_OK;
	}
	
private:
	SwitcherPanelAppDelegate*	mUiDelegate;
	int							mRefCount;
};


@implementation SwitcherPanelAppDelegate

@synthesize window;

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{

	mSwitcherDiscovery = NULL;
	mSwitcher = NULL;
	mMixEffectBlock = NULL;
	
	mSwitcherMonitor = new SwitcherMonitor(self);
	mMixEffectBlockMonitor = new MixEffectBlockMonitor(self);
	
	mMoveSliderDownwards = false;
	mCurrentTransitionReachedHalfway = false;
	
	mSwitcherDiscovery = CreateBMDSwitcherDiscoveryInstance();
	if (! mSwitcherDiscovery)
	{
		NSBeginAlertSheet(@"Could not create Switcher Discovery Instance.\nATEM Switcher Software may not be installed.\n",
							@"OK", nil, nil, window, self, @selector(sheetDidEndShouldTerminate:returnCode:contextInfo:), NULL, window, @"");
	}
	
	[self switcherDisconnected];		// start with switcher disconnected
    
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    mAddressTextField.stringValue = [prefs stringForKey:@"atem"];
    
    outgoing.intValue = [prefs integerForKey:@"outgoing"];
    incoming.intValue = [prefs integerForKey:@"incoming"];
    oscdevice.stringValue = [prefs objectForKey:@"oscdevice"];
    
    //	make an osc manager- i'm using i'm using a custom in-port to record a bunch of extra conversion for the display, but you can just make a "normal" manager
    manager = [[OSCManager alloc] init];
    
    
    [self portChanged:self];
    
    
    /// set up notifications
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didAddPorts:) name:AMSerialPortListDidAddPortsNotification object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didRemovePorts:) name:AMSerialPortListDidRemovePortsNotification object:nil];
	
	/// initialize port list to arm notifications
	[AMSerialPortList sharedPortList];
	[self listDevices];

    
}


- (void)controlTextDidEndEditing:(NSNotification *)aNotification {
    [self portChanged:self];
}

- (void) receivedOSCMessage:(OSCMessage *)m	{
    NSArray *address = [[m address] componentsSeparatedByString:@"/"];
 
    if ([[address objectAtIndex:1] isEqualToString:@"atem"] &&
        ([[address objectAtIndex:2] isEqualToString:@"preview"] || [[address objectAtIndex:2] isEqualToString:@"program"])) {
        
        [self activateChannel:[[address objectAtIndex:3] intValue] isProgram:[[address objectAtIndex:2] isEqualToString:@"program"]];
        
    } else if ([[address objectAtIndex:1] isEqualToString:@"atem"] &&
               [[address objectAtIndex:2] isEqualToString:@"transition"] &&
               [[address objectAtIndex:3] isEqualToString:@"bar"]) {
        if (mMoveSliderDownwards) 
            mMixEffectBlock->SetFloat(bmdSwitcherMixEffectBlockPropertyIdTransitionPosition, [[m valueAtIndex:0] floatValue]);
        else 
            mMixEffectBlock->SetFloat(bmdSwitcherMixEffectBlockPropertyIdTransitionPosition, 1.0-[[m valueAtIndex:0] floatValue]);
    } else if ([[address objectAtIndex:1] isEqualToString:@"atem"] &&
               [[address objectAtIndex:2] isEqualToString:@"transition"] &&
               [[address objectAtIndex:3] isEqualToString:@"cut"]) {
        if ([[m valueAtIndex:0] floatValue]==1.0)  mMixEffectBlock->PerformCut();
    } else if ([[address objectAtIndex:1] isEqualToString:@"atem"] &&
               [[address objectAtIndex:2] isEqualToString:@"transition"] &&
               [[address objectAtIndex:3] isEqualToString:@"auto"]) {
        if ([[m valueAtIndex:0] floatValue]==1.0)  mMixEffectBlock->PerformAutoTransition();
    } else if ([[address objectAtIndex:1] isEqualToString:@"atem"] &&
               [[address objectAtIndex:2] isEqualToString:@"transition"] &&
               [[address objectAtIndex:3] isEqualToString:@"ftb"]) {
        mMixEffectBlock->PerformFadeToBlack();
    } else if ([[address objectAtIndex:1] isEqualToString:@"atem"] &&
               [[address objectAtIndex:2] isEqualToString:@"nextusk"]) {
        switch ([[address objectAtIndex:3] intValue]) {
            case 0:
                switcherTransitionParameters->SetNextTransitionSelection(bmdSwitcherTransitionSelectionBackground); break;
            case 1:
                switcherTransitionParameters->SetNextTransitionSelection(bmdSwitcherTransitionSelectionKey1); break;
            case 2:
                switcherTransitionParameters->SetNextTransitionSelection(bmdSwitcherTransitionSelectionKey2); break;
            case 3:
                switcherTransitionParameters->SetNextTransitionSelection(bmdSwitcherTransitionSelectionKey3); break;
            case 4:
                switcherTransitionParameters->SetNextTransitionSelection(bmdSwitcherTransitionSelectionKey4); break;
            default:
                break;
        }
    } else if ([[address objectAtIndex:1] isEqualToString:@"atem"] &&
               [[address objectAtIndex:2] isEqualToString:@"usk"]) {
        int t = [[address objectAtIndex:3] intValue];
        
        if (t<=keyers.size()) {
            
            if ([[m value] floatValue] != 0.0) {
                std::list<IBMDSwitcherKey*>::iterator iter = keyers.begin();
                std::advance(iter, t-1);
                IBMDSwitcherKey * key = *iter;
                bool onAir;
                key->GetOnAir(&onAir);
                key->SetOnAir(!onAir);
                NSLog(@"dsk on %@",m);
            }
        }
    } else if ([[address objectAtIndex:1] isEqualToString:@"atem"] &&
               [[address objectAtIndex:2] isEqualToString:@"dsk"]) {
        int t = [[address objectAtIndex:3] intValue];
        
        if (t<=dsk.size()) {
            
            std::list<IBMDSwitcherDownstreamKey*>::iterator iter = dsk.begin();
            std::advance(iter, t-1);
            IBMDSwitcherDownstreamKey * key = *iter;
            
            bool isTransitioning;
            key->IsAutoTransitioning(&isTransitioning);
            if (!isTransitioning) key->PerformAutoTransition();
        }
    }

        
}


- (void) activateChannel:(int)channel isProgram:(BOOL)program {
    NSString *strip;

    if (program) {
        strip = @"program";
        [self send:self Channel:channel];
    } else {
        strip = @"preview";
    }
    
    
    for (int i = 0;i<=12;i++) {
        OSCMessage *newMsg = [OSCMessage createWithAddress:[NSString stringWithFormat:@"/atem/%@/%d",strip,i]];
        if (channel==i) {[newMsg addFloat:1.0];} else {[newMsg addFloat:0.0];}
        [outPort sendThisMessage:newMsg];
    }

    BMDSwitcherInputId InputId = channel;
    if (program) {
        @try {
            mMixEffectBlock->SetInt(bmdSwitcherMixEffectBlockPropertyIdProgramInput, InputId);
            
        }
        @catch (NSException *exception) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:exception.name];
            [alert runModal];
        }

        
    } else {
        @try {
            mMixEffectBlock->SetInt(bmdSwitcherMixEffectBlockPropertyIdPreviewInput, InputId);
        }
        @catch (NSException *exception) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setMessageText:exception.name];
            [alert runModal];
        }

        
    }
}

- (IBAction)portChanged:(id)sender {
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:[oscdevice stringValue] forKey:@"oscdevice"];
    [prefs setInteger:[outgoing intValue] forKey:@"outgoing"];
    [prefs setInteger:[incoming intValue] forKey:@"incoming"];    
    [prefs synchronize];
    
    [manager removeInput:inPort];
    [manager removeOutput:outPort];
    
        
    outPort = [manager createNewOutputToAddress:[oscdevice stringValue] atPort:[outgoing intValue] withLabel:@"atemOSC"];
    inPort = [manager createNewInputForPort:[incoming intValue] withLabel:@"atemOSC"];
    
    [manager setDelegate:self];

}

- (IBAction)tallyChanged:(id)sender {
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:[NSString stringWithFormat:@"%ld",(long)[[sender selectedItem] tag]] forKey:[NSString stringWithFormat:@"tally%ld",(long)[sender tag]] ];
}

- (void)applicationWillTerminate:(NSNotification*)aNotification
{
	mSwitcherMonitor->Release();
	mSwitcherMonitor = NULL;
	
	mMixEffectBlockMonitor->Release();
	mMixEffectBlockMonitor = NULL;

	if (mSwitcherDiscovery)
	{
		mSwitcherDiscovery->Release();
		mSwitcherDiscovery = NULL;
	}
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender
{
	return YES;
}

- (void)sheetDidEndShouldTerminate:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	[NSApp terminate:self];
}

//
// Actions
//


- (IBAction)helpButtonPressed:(id)sender {
    
    if ([sender tag] == 1) {
        
        if ([[tallyA itemArray] count]>0) {
            //set helptext
            [heltTextView setAlignment:NSLeftTextAlignment];
            
            NSMutableAttributedString * helpString = [[NSMutableAttributedString alloc] initWithString:@""];
            int i = 0;
            NSDictionary *infoAttribute = @{NSFontAttributeName: [[NSFontManager sharedFontManager] fontWithFamily:@"Monaco" traits:NSUnboldFontMask|NSUnitalicFontMask weight:5 size:12]};
            NSDictionary *addressAttribute = @{NSFontAttributeName: [[NSFontManager sharedFontManager] fontWithFamily:@"Helvetica" traits:NSBoldFontMask weight:5 size:12]};
            
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"Transitions:\n" attributes:addressAttribute]];
            
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tT-Bar: " attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/transition/bar\n" attributes:infoAttribute]];
            
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tCut: " attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/transition/cut\n" attributes:infoAttribute]];
            
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tAuto-Cut: " attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/transition/auto\n" attributes:infoAttribute]];
            
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\tFade-to-black: " attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"/atem/transition/ftb\n" attributes:infoAttribute]];
            
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\nUpstream Keyers:\n" attributes:addressAttribute]];
            for (int i = 0; i<keyers.size();i++) {
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tOn Air KEY %d: ",i+1] attributes:addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/usk/%d\n",i+1] attributes:infoAttribute]];
            }
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tBKGD: "] attributes:addressAttribute]];
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem//0\n"] attributes:infoAttribute]];
            for (int i = 0; i<keyers.size();i++) {
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tKEY %d: ",i+1] attributes:addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/nextusk/%d\n",i+1] attributes:infoAttribute]];
            }
            
            
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\nDownstream Keyers:\n" attributes:addressAttribute]];
            for (int i = 0; i<dsk.size();i++) {
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\tAuto-Transistion DSK%d: ",i+1] attributes:addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/dsk/%d\n",i+1] attributes:infoAttribute]];
            }

            
            
            [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:@"\nSources:\n" attributes:addressAttribute]];
            
            for (NSMenuItem *a in [tallyA itemArray]) {
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"\t%@: ",[a title]] attributes:addressAttribute]];
                [helpString appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"/atem/program/%d\n",i] attributes:infoAttribute]];
                i++;
            }
            
            
            
            [helpString addAttribute:NSForegroundColorAttributeName value:[NSColor whiteColor] range:NSMakeRange(0,helpString.length)];
            [[heltTextView textStorage] setAttributedString:helpString];
        }
        helpPanel.isVisible = YES;
    } else if ([sender tag]==2) {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://github.com/danielbuechele/atemOSC/"]];
    }
    
}



- (IBAction)connectButtonPressed:(id)sender
{

	NSString* address = [mAddressTextField stringValue];
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:address forKey:@"atem"];    
    [prefs synchronize];

	BMDSwitcherConnectToFailure			failReason;

	// Note that ConnectTo() can take several seconds to return, both for success or failure,
	// depending upon hostname resolution and network response times, so it may be best to
	// do this in a separate thread to prevent the main GUI thread blocking.
	HRESULT hr = mSwitcherDiscovery->ConnectTo((CFStringRef)address, &mSwitcher, &failReason);
	if (SUCCEEDED(hr))
	{
		[self switcherConnected];
	}
	else
	{
		NSString* reason;
		switch (failReason)
		{
			case bmdSwitcherConnectToFailureNoResponse:
				reason = @"No response from Switcher";
				break;
			case bmdSwitcherConnectToFailureIncompatibleFirmware:
				reason = @"Switcher has incompatible firmware";
				break;
			default:
				reason = @"Connection failed for unknown reason";
		}
		NSBeginAlertSheet(reason, @"OK", nil, nil, window, self, NULL, NULL, window, @"");
	}
}





- (void)switcherConnected
{
	HRESULT result;
	IBMDSwitcherMixEffectBlockIterator* iterator = NULL;
	IBMDSwitcherInputIterator* inputIterator = NULL;
    
    if ([[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)]) {
        self.activity = [[NSProcessInfo processInfo] beginActivityWithOptions:0x00FFFFFF reason:@"receiving OSC messages"];
    }
    
    OSCMessage *newMsg = [OSCMessage createWithAddress:@"/atem/led/green"];
    [newMsg addFloat:1.0];
    [outPort sendThisMessage:newMsg];
    newMsg = [OSCMessage createWithAddress:@"/atem/led/red"];
    [newMsg addFloat:0.0];
    [outPort sendThisMessage:newMsg];
	
	[mConnectButton setEnabled:NO];			// disable Connect button while connected
    [greenLight setHidden:NO];
    [redLight setHidden:YES];
	
	NSString* productName;
	if (FAILED(mSwitcher->GetProductName((CFStringRef*)&productName)))
	{
		NSLog(@"Could not get switcher product name");
		return;
	}
	
	[mSwitcherNameLabel setStringValue:productName];
	[productName release];
	
	mSwitcher->AddCallback(mSwitcherMonitor);
	
	// Create an InputMonitor for each input so we can catch any changes to input names
	result = mSwitcher->CreateIterator(IID_IBMDSwitcherInputIterator, (void**)&inputIterator);
	if (SUCCEEDED(result))
	{
		IBMDSwitcherInput* input = NULL;
		
		// For every input, install a callback to monitor property changes on the input
		while (S_OK == inputIterator->Next(&input))
		{
			InputMonitor* inputMonitor = new InputMonitor(input, self);
			input->Release();
			mInputMonitors.push_back(inputMonitor);
		}
		inputIterator->Release();
		inputIterator = NULL;
	}
		
    


    
    
	// Get the mix effect block iterator
	result = mSwitcher->CreateIterator(IID_IBMDSwitcherMixEffectBlockIterator, (void**)&iterator);
	if (FAILED(result))
	{
		NSLog(@"Could not create IBMDSwitcherMixEffectBlockIterator iterator");
		return;
	}
	
	// Use the first Mix Effect Block
	if (S_OK != iterator->Next(&mMixEffectBlock))
	{
		NSLog(@"Could not get the first IBMDSwitcherMixEffectBlock");
		return;
	}
    
    
    //Upstream Keyer
    IBMDSwitcherKeyIterator* keyIterator = NULL;
    result = mMixEffectBlock->CreateIterator(IID_IBMDSwitcherKeyIterator, (void**)&keyIterator);
    IBMDSwitcherKey* key = NULL;
    while (S_OK == keyIterator->Next(&key)) {
        keyers.push_back(key);
    }
    keyIterator->Release();
    keyIterator = NULL;
    
    
    //Downstream Keyer
    IBMDSwitcherDownstreamKeyIterator* dskIterator = NULL;
    result = mSwitcher->CreateIterator(IID_IBMDSwitcherDownstreamKeyIterator, (void**)&dskIterator);
    IBMDSwitcherDownstreamKey* downstreamKey = NULL;
    while (S_OK == dskIterator->Next(&downstreamKey)) {
        dsk.push_back(downstreamKey);
    }
    dskIterator->Release();
    dskIterator = NULL;
    
    
    
    switcherTransitionParameters = NULL;
    mMixEffectBlock->QueryInterface(IID_IBMDSwitcherTransitionParameters, (void**)&switcherTransitionParameters);
    
    
	mMixEffectBlock->AddCallback(mMixEffectBlockMonitor);
	
	[self mixEffectBlockBoxSetEnabled:YES];
	[self updatePopupButtonItems];
	[self updateSliderPosition];
	[self updateTransitionFramesTextField];
	[self updateFTBFramesTextField];
	
finish:
	if (iterator)
		iterator->Release();
}

- (void)switcherDisconnected
{
	if (self.activity) {
        [[NSProcessInfo processInfo] endActivity:self.activity];
    }
    
    self.activity = nil;
    
    OSCMessage *newMsg = [OSCMessage createWithAddress:@"/atem/led/green"];
    [newMsg addFloat:0.0];
    [outPort sendThisMessage:newMsg];
    newMsg = [OSCMessage createWithAddress:@"/atem/led/red"];
    [newMsg addFloat:1.0];
    [outPort sendThisMessage:newMsg];
    
    [mConnectButton setEnabled:YES];			// enable connect button so user can re-connect
	[mSwitcherNameLabel setStringValue:@""];
    [greenLight setHidden:YES];
    [redLight setHidden:NO];
	
    
	[self mixEffectBlockBoxSetEnabled:NO];
	
	// cleanup resources created when switcher was connected
	for (std::list<InputMonitor*>::iterator it = mInputMonitors.begin(); it != mInputMonitors.end(); ++it)
	{
		(*it)->Release();
	}
	mInputMonitors.clear();
	
	if (mMixEffectBlock)
	{
		mMixEffectBlock->RemoveCallback(mMixEffectBlockMonitor);
		mMixEffectBlock->Release();
		mMixEffectBlock = NULL;
	}
	
	if (mSwitcher)
	{
		mSwitcher->RemoveCallback(mSwitcherMonitor);
		mSwitcher->Release();
		mSwitcher = NULL;
	}
}

//
// GUI updates
//
- (void)updatePopupButtonItems
{
	HRESULT result;
	IBMDSwitcherInputIterator* inputIterator = NULL;
	IBMDSwitcherInput* input = NULL;
	
	result = mSwitcher->CreateIterator(IID_IBMDSwitcherInputIterator, (void**)&inputIterator);
	if (FAILED(result))
	{
		NSLog(@"Could not create IBMDSwitcherInputIterator iterator");
		return;
	}
	


	while (S_OK == inputIterator->Next(&input))
	{
		NSString* name;
		BMDSwitcherInputId id;
        
        
        
		input->GetInputId(&id);
		input->GetString(bmdSwitcherInputPropertyIdLongName, (CFStringRef*)&name);
		
        [tallyA addItemWithTitle:name];
		[[tallyA lastItem] setTag:id];
        
        [tallyB addItemWithTitle:name];
		[[tallyB lastItem] setTag:id];
        
        [tallyC addItemWithTitle:name];
		[[tallyC lastItem] setTag:id];
        
        [tallyD addItemWithTitle:name];
		[[tallyD lastItem] setTag:id];
        
		
		input->Release();
		[name release];
	}
	inputIterator->Release();
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    
    [tallyA selectItemAtIndex:[[prefs objectForKey:@"tally0"] intValue]];
    [tallyB selectItemAtIndex:[[prefs objectForKey:@"tally1"] intValue]];
    [tallyC selectItemAtIndex:[[prefs objectForKey:@"tally2"] intValue]];
    [tallyD selectItemAtIndex:[[prefs objectForKey:@"tally3"] intValue]];
    
    
    
    
	[self updateProgramButtonSelection];
	[self updatePreviewButtonSelection];
}

- (void)updateProgramButtonSelection
{
    
    
	BMDSwitcherInputId	programId;
	mMixEffectBlock->GetInt(bmdSwitcherMixEffectBlockPropertyIdProgramInput, &programId);

    
    [self activateChannel:programId isProgram:YES];
}

- (void)updatePreviewButtonSelection
{
	BMDSwitcherInputId	previewId;
	mMixEffectBlock->GetInt(bmdSwitcherMixEffectBlockPropertyIdPreviewInput, &previewId);

    
    [self activateChannel:previewId isProgram:NO];
}

- (void)updateInTransitionState
{
	bool inTransition;
	mMixEffectBlock->GetFlag(bmdSwitcherMixEffectBlockPropertyIdInTransition, &inTransition);
	
	if (inTransition == false)
	{
		// Toggle the starting orientation of slider handle if a transition has passed through halfway
		if (mCurrentTransitionReachedHalfway)
		{
			mMoveSliderDownwards = ! mMoveSliderDownwards;
			[self updateSliderPosition];
		}
		
		mCurrentTransitionReachedHalfway = false;
	}
}

- (void)updateSliderPosition
{
	double position;
	mMixEffectBlock->GetFloat(bmdSwitcherMixEffectBlockPropertyIdTransitionPosition, &position);
	
	// Record when transition passes halfway so we can flip orientation of slider handle at the end of transition
	mCurrentTransitionReachedHalfway = (position >= 0.50);

	double sliderPosition = position * 100;
	if (mMoveSliderDownwards)
		sliderPosition = 100 - position * 100;		// slider handle moving in opposite direction
	

    
    OSCMessage *newMsg = [OSCMessage createWithAddress:@"/atem/transition/bar"];
    [newMsg addFloat:1.0-sliderPosition/100];
    [outPort sendThisMessage:newMsg];
}

- (void)updateTransitionFramesTextField
{
	int64_t framesRemaining;
	mMixEffectBlock->GetInt(bmdSwitcherMixEffectBlockPropertyIdTransitionFramesRemaining, &framesRemaining);

}

- (void)updateFTBFramesTextField
{
	int64_t framesRemaining;
	mMixEffectBlock->GetInt(bmdSwitcherMixEffectBlockPropertyIdFadeToBlackFramesRemaining, &framesRemaining);

}

- (void)mixEffectBlockBoxSetEnabled:(bool)enabled
{


}







# pragma mark Serial Port Stuff

- (IBAction)initPort:(id)sender {
    
    
    NSString *deviceName = [serialSelectMenu titleOfSelectedItem];

    if (![deviceName isEqualToString:[port bsdPath]]) {
        
        
        [port close];
        
        [self setPort:[[[AMSerialPort alloc] init:deviceName withName:deviceName type:(NSString*)CFSTR(kIOSerialBSDModemType)] autorelease]];
        [port setDelegate:self];
        
        if ([port open]) {

            NSLog(@"successfully connected");
            
            [connectButton setEnabled:NO];
            [serialSelectMenu setEnabled:NO];
            [tallyGreenLight setHidden:NO];
            [tallyRedLight setHidden:YES];
            
            [port setSpeed:B9600]; 
            
            
            // listen for data in a separate thread
            [port readDataInBackground];
            
            
        } else { // an error occured while creating port
            
            NSLog(@"error connecting");
            //[serialScreenMessage setStringValue:@"Error Trying to Connect..."];
            [self setPort:nil];
            
        }
    }
}




- (void)serialPortReadData:(NSDictionary *)dataDictionary
{
    
    AMSerialPort *sendPort = [dataDictionary objectForKey:@"serialPort"];
    NSData *data = [dataDictionary objectForKey:@"data"];
    
    if ([data length] > 0) {
        
        NSString *receivedText = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
        NSLog(@"Serial Port Data Received: %@",receivedText);
        
        
        //Typically, I arrange my serial messages coming from the Arduino in chunks, with the
        //data being separated by a comma or semicolon. If you're doing something similar, a 
        //variant of the following command is invaluable. 
        
        //NSArray *dataArray = [receivedText componentsSeparatedByString:@","];
        
        
        // continue listening
        [sendPort readDataInBackground];
        
    } else { 
        // port closed
        NSLog(@"Port was closed on a readData operation...not good!");
        [connectButton setEnabled:YES];
        [serialSelectMenu setEnabled:YES];
        [tallyGreenLight setHidden:YES];
        [tallyRedLight setHidden:NO];
    }
    
}

- (void)listDevices
{
     //get an port enumerator
    NSEnumerator *enumerator = [AMSerialPortList portEnumerator];
    AMSerialPort *aPort;
    [serialSelectMenu removeAllItems];
    
    while (aPort = [enumerator nextObject]) {
        [serialSelectMenu addItemWithTitle:[aPort bsdPath]];
    }
}

- (IBAction)send:(id)sender Channel:(int)channel {


    if([port isOpen]) {
        if (channel>0 && channel<7) {
            
            if (channel == [[tallyA selectedItem] tag]) {NSLog(@"A");[port writeString:@"A" usingEncoding:NSUTF8StringEncoding error:NULL];}
            else if (channel == [[tallyB selectedItem] tag]) {NSLog(@"B");[port writeString:@"B" usingEncoding:NSUTF8StringEncoding error:NULL];}
            else if (channel == [[tallyC selectedItem] tag]) {NSLog(@"C");[port writeString:@"C" usingEncoding:NSUTF8StringEncoding error:NULL];}
            else if (channel == [[tallyD selectedItem] tag]) {NSLog(@"D");[port writeString:@"D" usingEncoding:NSUTF8StringEncoding error:NULL];}
            else {[port writeString:@"0" usingEncoding:NSUTF8StringEncoding error:NULL];};

        } else {
            [port writeString:@"0" usingEncoding:NSUTF8StringEncoding error:NULL];
        }
    }
}

- (AMSerialPort *)port
{
    return port;
}

- (void)setPort:(AMSerialPort *)newPort
{
    id old = nil;
    
    if (newPort != port) {
        old = port;
        port = [newPort retain];
        [old release];
    }
}


# pragma mark Notifications

- (void)didAddPorts:(NSNotification *)theNotification
{
    NSLog(@"A port was added");
    [self listDevices];
}

- (void)didRemovePorts:(NSNotification *)theNotification
{
    NSLog(@"A port was removed");
    [self listDevices];
}




@end
