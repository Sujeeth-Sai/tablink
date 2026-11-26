import AppKit
import AVFoundation
import VideoToolbox
import TabLinkCore
final class VideoDecoder {
    let layer=AVSampleBufferDisplayLayer()
    private let queue=DispatchQueue(label:"app.tablink.video",qos:.userInteractive)
    private var format:CMVideoFormatDescription?
    private var session:VTDecompressionSession?
    private var sps:Data?;private var pps:Data?
    private let lock=NSLock();private var pending=0
    var onResolution:((Int,Int)->Void)?
    var onDecoded:((CVPixelBuffer)->Void)?
    var decodedCount=0;var errorCount=0;var hardwareAccelerated=false
    init() {layer.videoGravity = .resizeAspect;layer.backgroundColor=NSColor.black.cgColor}
    func consume(_ data:Data,config:Bool) {queue.async { [weak self] in self?.decode(data,config:config) }}
    func finish(_ completion:@escaping()->Void) {queue.async{[weak self] in if let s=self?.session {VTDecompressionSessionWaitForAsynchronousFrames(s)};DispatchQueue.main.async(execute:completion)}}
    private func decode(_ data:Data,config:Bool) {
        let units=AnnexB.units(data)
        for unit in units {guard let first=unit.first else{continue};if first & 31 == 7 {sps=unit};if first & 31 == 8 {pps=unit}}
        if config,let s=sps,let p=pps {
            var newFormat:CMFormatDescription?
            let status=s.withUnsafeBytes { sr in p.withUnsafeBytes { pr in
                let pointers=[sr.baseAddress!.assumingMemoryBound(to:UInt8.self),pr.baseAddress!.assumingMemoryBound(to:UInt8.self)]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator:kCFAllocatorDefault,parameterSetCount:2,parameterSetPointers:pointers,parameterSetSizes:[s.count,p.count],nalUnitHeaderLength:4,formatDescriptionOut:&newFormat)
            }}
            guard status==noErr,let f=newFormat else{errorCount+=1;return}
            if let old=session {VTDecompressionSessionWaitForAsynchronousFrames(old);VTDecompressionSessionInvalidate(old)};session=nil;format=f
            var callback=VTDecompressionOutputCallbackRecord(decompressionOutputCallback:{refcon,_,status,_,image,_,_ in
                guard let refcon=refcon else{return};let decoder=Unmanaged<VideoDecoder>.fromOpaque(refcon).takeUnretainedValue()
                guard status==noErr,let image=image else {decoder.errorCount+=1;return};decoder.render(image)
            },decompressionOutputRefCon:Unmanaged.passUnretained(self).toOpaque())
            let spec=[kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder:true] as CFDictionary
            let attributes=[kCVPixelBufferPixelFormatTypeKey:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,kCVPixelBufferIOSurfacePropertiesKey:[:]] as CFDictionary
            let create=VTDecompressionSessionCreate(allocator:kCFAllocatorDefault,formatDescription:f,decoderSpecification:spec,imageBufferAttributes:attributes,outputCallback:&callback,decompressionSessionOut:&session)
            if create != noErr {errorCount+=1;return}
            if let sess=session {var hardware:CFTypeRef?;VTSessionCopyProperty(sess,key:kVTDecompressionPropertyKey_UsingHardwareAcceleratedVideoDecoder,allocator:kCFAllocatorDefault,valueOut:&hardware);hardwareAccelerated=(hardware as? Bool)==true}
            let size=CMVideoFormatDescriptionGetDimensions(f);onResolution?(Int(size.width),Int(size.height))
            DispatchQueue.main.async { [weak self] in self?.layer.flushAndRemoveImage() };return
        }
        guard let format=format,let session=session else{return}
        var avcc=Data()
        for unit in units {guard let first=unit.first,first & 31 != 7,first & 31 != 8 else{continue};avcc.put(UInt32(unit.count));avcc.append(unit)}
        guard !avcc.isEmpty else{return}
        var block:CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator:kCFAllocatorDefault,memoryBlock:nil,blockLength:avcc.count,blockAllocator:kCFAllocatorDefault,customBlockSource:nil,offsetToData:0,dataLength:avcc.count,flags:0,blockBufferOut:&block)==noErr,let block=block else{errorCount+=1;return}
        _=avcc.withUnsafeBytes {CMBlockBufferReplaceDataBytes(with:$0.baseAddress!,blockBuffer:block,offsetIntoDestination:0,dataLength:avcc.count)}
        var size=avcc.count;var sample:CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator:kCFAllocatorDefault,dataBuffer:block,formatDescription:format,sampleCount:1,sampleTimingEntryCount:0,sampleTimingArray:nil,sampleSizeEntryCount:1,sampleSizeArray:&size,sampleBufferOut:&sample)==noErr,let sample=sample else{errorCount+=1;return}
        let result=VTDecompressionSessionDecodeFrame(session,sampleBuffer:sample,flags:[._EnableAsynchronousDecompression,._EnableTemporalProcessing],frameRefcon:nil,infoFlagsOut:nil)
        if result != noErr {errorCount+=1}
    }
    private func render(_ image:CVPixelBuffer) {
        decodedCount+=1;onDecoded?(image)
        // Drop stale decoded frames, preserving all H.264 reference frames in the decoder.
        lock.lock();if pending>=2 {lock.unlock();return};pending+=1;lock.unlock()
        var description:CMVideoFormatDescription?;var sample:CMSampleBuffer?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:image,formatDescriptionOut:&description)
        var timing=CMSampleTimingInfo(duration:.invalid,presentationTimeStamp:.zero,decodeTimeStamp:.invalid)
        guard let d=description,CMSampleBufferCreateReadyWithImageBuffer(allocator:kCFAllocatorDefault,imageBuffer:image,formatDescription:d,sampleTiming:&timing,sampleBufferOut:&sample)==noErr,let sample=sample else{lock.lock();pending-=1;lock.unlock();return}
        if let a=CMSampleBufferGetSampleAttachmentsArray(sample,createIfNecessary:true) {let dict=unsafeBitCast(CFArrayGetValueAtIndex(a,0),to:CFMutableDictionary.self);CFDictionarySetValue(dict,Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())}
        DispatchQueue.main.async { [weak self] in guard let self=self else{return};defer{self.lock.lock();self.pending-=1;self.lock.unlock()};if self.layer.status == .failed {self.layer.flush()};self.layer.enqueue(sample)}
    }
    deinit {if let session=session {VTDecompressionSessionInvalidate(session)}}
}
