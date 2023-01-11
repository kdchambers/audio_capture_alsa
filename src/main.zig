const std = @import("std");
const alsa = @cImport({
    @cInclude("alsa/asoundlib.h");
});
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("string.h");
    @cInclude("stdlib.h");
});

var stream: alsa.snd_pcm_stream_t = alsa.SND_PCM_STREAM_PLAYBACK;

extern fn snd_ctl_open(ctl: **alsa.snd_ctl_t, name: [*:0]u8, mode: i32) i32;

pub fn main() !void {
    std.log.info("Working!", .{});
    try deviceList();
}

fn deviceList() !void {
    var handle: *alsa.snd_ctl_t = undefined;
    var card: i32 = undefined;
    var err: i32 = undefined;
    var dev: i32 = undefined;
    var idx: i32 = undefined;
    var info: *alsa.snd_ctl_card_info_t = undefined;
    var pcminfo: *alsa.snd_pcm_info_t = undefined;

    {
        const size = alsa.snd_ctl_card_info_sizeof();
        info = @ptrCast(*alsa.snd_ctl_card_info_t, c.malloc(size));
        _ = c.memset(info, 0, size);
    }

    {
        const size = alsa.snd_pcm_info_sizeof();
        pcminfo = @ptrCast(*alsa.snd_pcm_info_t, c.malloc(size));
        _ = c.memset(info, 0, size);
    }
    defer c.free(info);
    defer c.free(pcminfo);

    card = -1;
    if (alsa.snd_card_next(&card) < 0) {
        std.log.err("No soundcards found", .{});
        return;
    }

    if (card < 0) {
        std.log.err("No soundcards found", .{});
        return;
    }

    const print = std.debug.print;

    const stream_name = alsa.snd_pcm_stream_name(stream);
    print("**** List of {s} Hardware devices ****\n", .{stream_name});

    outer: while (card >= 0) {
        var name_buffer: [32]u8 = undefined;
        const name = try std.fmt.bufPrintZ(name_buffer[0..32], "hw:{d}", .{card});
        err = snd_ctl_open(&handle, name, 0);
        if (err < 0) {
            std.log.err("Open ctl", .{});
            break;
        }
        err = alsa.snd_ctl_card_info(handle, info);
        if (err < 0) {
            std.log.err("Open ctl", .{});
            break;
        }
        dev = -1;
        while (true) {
            var count: u32 = undefined;
            if (alsa.snd_ctl_pcm_next_device(handle, &dev) < 0) {
                std.log.err("Failed to open device for card hw:{d}", .{card});
                return;
            }
            if (dev < 0)
                break;

            alsa.snd_pcm_info_set_device(pcminfo, @intCast(u32, dev));
            alsa.snd_pcm_info_set_subdevice(pcminfo, 0);
            alsa.snd_pcm_info_set_stream(pcminfo, stream);

            err = alsa.snd_ctl_pcm_info(handle, pcminfo);
            if (err < 0) {
                if (err != -alsa.ENOENT)
                    std.log.err("Control digital audio info ({d}): {s}", .{ card, alsa.snd_strerror(err) });
                continue;
            }

            print("card {d}: {s} [{s}], device {d}: {s} [{s}]\n", .{
                card,
                alsa.snd_ctl_card_info_get_id(info),
                alsa.snd_ctl_card_info_get_name(info),
                dev,
                alsa.snd_pcm_info_get_id(pcminfo),
                alsa.snd_pcm_info_get_name(pcminfo),
            });
            count = alsa.snd_pcm_info_get_subdevices_count(pcminfo);
            print("  Subdevices: {d}/{d}\n", .{
                alsa.snd_pcm_info_get_subdevices_avail(pcminfo),
                count,
            });
            idx = 0;
            inner: while (idx < count) : (idx += 1) {
                alsa.snd_pcm_info_set_subdevice(pcminfo, @intCast(u32, idx));
                err = alsa.snd_ctl_pcm_info(handle, pcminfo);
                if (err < 0) {
                    std.log.err("control digital audo playback info ({d}): {s}", .{
                        card,
                        alsa.snd_strerror(err),
                    });
                    continue :inner;
                }
                print("  Subdevice #{d}: {s}\n", .{ idx, alsa.snd_pcm_info_get_subdevice_name(pcminfo) });
            }
        }
        _ = alsa.snd_ctl_close(handle);
        if (alsa.snd_card_next(&card) < 0) {
            break :outer;
        }
    }
}
