package com.vshot.kafka.controller;

import com.vshot.kafka.producer.KafkaProducerService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/kafka")
public class TestController {

    @Autowired
    private KafkaProducerService kafkaProducerService;

    @PostMapping("/execute-producer")
    public String executeFirstProducer(@RequestParam("msg") String msg){

        kafkaProducerService.sendMessage(msg);
        return "producer Executed SuccessFully";
    }

}
